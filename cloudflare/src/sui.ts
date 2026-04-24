// Sui testnet client + PTB builder for workout submission.
//
// Configuration (all optional — pipeline gracefully no-ops when absent):
//   SUI_NETWORK           — "testnet" | "mainnet" | custom RPC URL
//   SUI_PACKAGE_ID        — 0x... published package address
//   SUI_REWARDS_ENGINE_ID — 0x... shared RewardsEngine object
//   SUI_ORACLE_CAP_ID     — 0x... owned OracleCap object
//   SUI_VERSION_OBJECT_ID — 0x... shared Version object
//   SUI_OPERATOR_KEY      — base64 Ed25519 private key that owns the
//                           UserProfile objects and pays gas
//   ORACLE_PRIVATE_KEY    — base64 Ed25519 secret key whose pubkey is
//                           stored in OracleCap. Signs the attestation
//                           digest the contract verifies.
//
// Oracle and operator are two distinct roles:
//   - Operator: Sui account that signs the PTB (pays gas, owns profiles)
//   - Oracle:   Ed25519 keypair whose signature over a canonical digest
//               the contract verifies. Never holds Sui directly.

import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from "@mysten/sui/jsonRpc";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import { fromBase64, toHex } from "@mysten/sui/utils";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { ed25519 } from "@noble/curves/ed25519.js";
import { blake2b } from "@noble/hashes/blake2.js";

/// Return the raw 32-byte Ed25519 seed from either a `suiprivkey1...`
/// bech32 string or a plain base64 seed.
function rawSeed(s: string): Uint8Array {
    if (s.startsWith("suiprivkey")) {
        return decodeSuiPrivateKey(s).secretKey;
    }
    const raw = fromBase64(s);
    return raw.length === 32 ? raw : raw.slice(0, 32);
}

/// Build an Ed25519Keypair from either representation. The SDK's
/// `fromSecretKey` accepts the suiprivkey string directly; for raw
/// base64 we feed it the decoded bytes.
export function operatorKeypair(s: string): Ed25519Keypair {
    if (s.startsWith("suiprivkey")) {
        return Ed25519Keypair.fromSecretKey(s);
    }
    return Ed25519Keypair.fromSecretKey(rawSeed(s));
}

export interface SuiEnv {
    SUI_NETWORK?: string;
    SUI_PACKAGE_ID?: string;
    SUI_REWARDS_ENGINE_ID?: string;
    SUI_ORACLE_CAP_ID?: string;
    SUI_VERSION_OBJECT_ID?: string;
    SUI_OPERATOR_KEY?: string;
    SUI_OPERATOR_KEYS?: string;
    ORACLE_PRIVATE_KEY?: string;
}

export function hasSuiConfig(env: SuiEnv): boolean {
    const hasAnyOperator =
        !!env.SUI_OPERATOR_KEY ||
        !!(env.SUI_OPERATOR_KEYS && env.SUI_OPERATOR_KEYS.trim().length > 0);
    return !!(
        env.SUI_PACKAGE_ID &&
        env.SUI_REWARDS_ENGINE_ID &&
        env.SUI_ORACLE_CAP_ID &&
        env.SUI_VERSION_OBJECT_ID &&
        hasAnyOperator &&
        env.ORACLE_PRIVATE_KEY
    );
}

/// Parse the pool of available operator keys.
///
/// Priority:
///   1. SUI_OPERATOR_KEYS (comma-separated) — multi-key fanout
///   2. SUI_OPERATOR_KEY (single) — legacy single-operator mode
///
/// Empty entries (blanks, whitespace) are dropped so a trailing comma
/// or a `,,` doesn't produce phantom keys. Returns `[]` when nothing
/// is configured — callers should guard with hasSuiConfig first.
export function operatorKeyPool(env: SuiEnv): string[] {
    if (env.SUI_OPERATOR_KEYS && env.SUI_OPERATOR_KEYS.trim().length > 0) {
        const parts = env.SUI_OPERATOR_KEYS
            .split(",")
            .map((s) => s.trim())
            .filter((s) => s.length > 0);
        if (parts.length > 0) return parts;
    }
    return env.SUI_OPERATOR_KEY ? [env.SUI_OPERATOR_KEY] : [];
}

/// Deterministic athlete-to-operator mapping.
///
/// We hash the athlete id (cheap FNV-1a 32-bit) and mod by the pool
/// size. The mapping is stable for the lifetime of the pool, which
/// matters because each operator owns the UserProfile objects it
/// minted — if we rotated the mapping, the stored profile_object_id
/// in sui_user_profiles would belong to the wrong signer and the
/// submit would fail with an ownership error.
///
/// When operators are added to SUI_OPERATOR_KEYS the mapping for
/// *existing* athletes may shift, but the D1 row already stores the
/// concrete profile_object_id so we only need a keypair that can sign
/// mutations on that object. We solve this by making the "owner"
/// operator the one that was current *at mint time* — the submit
/// caller looks up the profile and then signs with the operator whose
/// address owns it. See `operatorKeypairForAthlete`.
export function operatorKeypairForAthlete(
    env: SuiEnv,
    athleteId: string
): Ed25519Keypair {
    const pool = operatorKeyPool(env);
    if (pool.length === 0) {
        throw new Error("no_operator_keys_configured");
    }
    if (pool.length === 1) {
        return operatorKeypair(pool[0]);
    }
    const idx = fnv1a32(athleteId) % pool.length;
    return operatorKeypair(pool[idx]);
}

/// When the DB already knows which operator owns an athlete's
/// UserProfile (stored in sui_user_profiles.operator_address), use
/// this to fetch a keypair that matches. Returns null when no key in
/// the pool matches the address — caller should surface that as a
/// misconfiguration (e.g. rotating keys requires re-minting profiles).
export function operatorKeypairByAddress(
    env: SuiEnv,
    address: string
): Ed25519Keypair | null {
    const pool = operatorKeyPool(env);
    for (const k of pool) {
        try {
            const kp = operatorKeypair(k);
            if (kp.getPublicKey().toSuiAddress() === address) return kp;
        } catch { /* skip malformed */ }
    }
    return null;
}

function fnv1a32(s: string): number {
    // FNV-1a 32-bit — tiny, deterministic, no DB hit. We only need
    // "evenly spread" distribution across a small pool (2..N ops).
    let h = 0x811c9dc5;
    for (let i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
    }
    return h >>> 0;
}

export function suiClient(env: SuiEnv): SuiJsonRpcClient {
    const net = (env.SUI_NETWORK || "testnet") as "mainnet" | "testnet" | "devnet" | "localnet";
    const url = net.startsWith("http") ? env.SUI_NETWORK! : getJsonRpcFullnodeUrl(net);
    return new SuiJsonRpcClient({ url, network: net });
}

/** Oracle attestation per the Move contract's expected digest format:
 *    BLAKE2b-256(
 *      athlete || nonce || expires_at_ms_be ||
 *      workout_type || timestamp_ms_be || duration_s_be ||
 *      distance_m_be || calories_be || walrus_blob_id || reward_amount_be
 *    )
 *  All integers are big-endian LEB-less; plain fixed-width big-endian. */
export function buildAttestationDigest(input: {
    athlete: string;              // 0x-prefixed sui address
    nonce: Uint8Array;            // 16 bytes, random per submission
    expiresAtMs: bigint;
    workoutType: number;          // u8
    timestampMs: bigint;
    durationS: number;            // u32
    distanceM: number;            // u32
    calories: number;             // u32
    walrusBlobId: Uint8Array;
    rewardAmount: bigint;         // u64
}): Uint8Array {
    const addr = hexToBytes(input.athlete);
    const parts: Uint8Array[] = [
        addr,
        input.nonce,
        u64BE(input.expiresAtMs),
        new Uint8Array([input.workoutType]),
        u64BE(input.timestampMs),
        u32BE(input.durationS),
        u32BE(input.distanceM),
        u32BE(input.calories),
        input.walrusBlobId,
        u64BE(input.rewardAmount),
    ];
    const concatenated = concat(parts);
    return blake2b(concatenated, { dkLen: 32 });
}

export function signAttestation(
    oraclePrivateKey: string,
    digest: Uint8Array
): Uint8Array {
    return ed25519.sign(digest, rawSeed(oraclePrivateKey));
}

/** Build + submit a `rewards_engine::submit_workout` transaction.
 *  Returns the executed tx digest (on success). Caller is responsible
 *  for ensuring hasSuiConfig(env) is true.
 *
 *  `operator` is the exact keypair that should sign — it MUST own
 *  `profileObjectId`. Pass `null` / omit to fall back to the first
 *  pool key (for backwards-compatible single-operator callers). */
export async function submitWorkoutOnChain(
    env: SuiEnv,
    input: {
        athlete: string;
        profileObjectId: string;    // UserProfile owned by operator
        workoutType: number;
        timestampMs: bigint;
        durationS: number;
        distanceM: number;
        calories: number;
        walrusBlobId: Uint8Array;   // raw bytes
        rewardAmount: bigint;
    },
    operator?: Ed25519Keypair
): Promise<{ txDigest: string; eventDigests: unknown[] }> {
    const client = suiClient(env);

    const nonce = crypto.getRandomValues(new Uint8Array(16));
    const expiresAtMs = BigInt(Date.now() + 15 * 60_000);

    const digest = buildAttestationDigest({
        athlete: input.athlete,
        nonce,
        expiresAtMs,
        workoutType: input.workoutType,
        timestampMs: input.timestampMs,
        durationS: input.durationS,
        distanceM: input.distanceM,
        calories: input.calories,
        walrusBlobId: input.walrusBlobId,
        rewardAmount: input.rewardAmount,
    });
    const signature = signAttestation(env.ORACLE_PRIVATE_KEY!, digest);

    const tx = new Transaction();
    tx.moveCall({
        target: `${env.SUI_PACKAGE_ID}::rewards_engine::submit_workout`,
        arguments: [
            tx.object(env.SUI_REWARDS_ENGINE_ID!),
            tx.object(env.SUI_ORACLE_CAP_ID!),
            tx.object(env.SUI_VERSION_OBJECT_ID!),
            tx.object(input.profileObjectId),
            tx.pure.address(input.athlete),
            tx.pure.vector("u8", Array.from(nonce)),
            tx.pure.u64(expiresAtMs),
            tx.pure.u8(input.workoutType),
            tx.pure.u64(input.timestampMs),
            tx.pure.u32(input.durationS),
            tx.pure.u32(input.distanceM),
            tx.pure.u32(input.calories),
            tx.pure.vector("u8", Array.from(input.walrusBlobId)),
            tx.pure.u64(input.rewardAmount),
            tx.pure.vector("u8", Array.from(signature)),
            tx.pure.vector("u8", Array.from(digest)),
        ],
    });

    // Caller is expected to pass the operator that owns the
    // profileObjectId. When they don't, we fall back to the first
    // keypair in the pool — that path is for legacy single-operator
    // deploys where there's only one possible signer.
    const signer = operator ?? operatorKeypairForAthlete(env, input.athlete);
    const res = await client.signAndExecuteTransaction({
        signer,
        transaction: tx,
        options: { showEffects: true, showEvents: true },
    });
    return {
        txDigest: res.digest,
        eventDigests: res.events ?? [],
    };
}

/** Get the $SWEAT coin balance for an address. Returns "0" when
 *  package not yet published. */
export async function getSweatBalance(
    env: SuiEnv,
    address: string
): Promise<string> {
    if (!env.SUI_PACKAGE_ID) return "0";
    const client = suiClient(env);
    try {
        const coinType = `${env.SUI_PACKAGE_ID}::sweat::SWEAT`;
        const balance = await client.getBalance({ owner: address, coinType });
        return balance.totalBalance;
    } catch {
        return "0";
    }
}

/** Reverse SuiNS lookup. Returns the first name registered to the
 *  address (e.g. "alice.sui") or null. Runs on both testnet and
 *  mainnet — the resolver is deployed on each network separately.
 *  Silent-on-error: a node outage or unregistered address returns null
 *  so callers can fall back to OAuth-provided name. */
export async function resolveSuiNS(
    env: SuiEnv,
    address: string
): Promise<string | null> {
    if (!env.SUI_NETWORK && !env.SUI_PACKAGE_ID) return null;
    try {
        const client = suiClient(env);
        const res = await client.resolveNameServiceNames({
            address, limit: 1,
        });
        return res.data?.[0] ?? null;
    } catch {
        return null;
    }
}

/** Derive the primary operator's Sui address, useful for the status
 *  endpoint + setup scripts. Returns the address of the FIRST key in
 *  the pool (or the legacy single key when only that's set). */
export function operatorAddress(env: SuiEnv): string | null {
    const pool = operatorKeyPool(env);
    if (pool.length === 0) return null;
    try {
        const kp = operatorKeypair(pool[0]);
        return kp.getPublicKey().toSuiAddress();
    } catch {
        return null;
    }
}

/** Return every operator address in the pool. Used by the ownership
 *  lookup path — when ensureUserProfile needs to know which existing
 *  operator owns a given UserProfile, we can match on address. */
export function operatorAddresses(env: SuiEnv): string[] {
    const pool = operatorKeyPool(env);
    const out: string[] = [];
    for (const k of pool) {
        try { out.push(operatorKeypair(k).getPublicKey().toSuiAddress()); }
        catch { /* skip malformed */ }
    }
    return out;
}

// ---------- helpers ----------

function hexToBytes(hex: string): Uint8Array {
    const h = hex.startsWith("0x") ? hex.slice(2) : hex;
    const padded = h.length % 2 === 0 ? h : "0" + h;
    const out = new Uint8Array(padded.length / 2);
    for (let i = 0; i < out.length; i++) {
        out[i] = parseInt(padded.substr(i * 2, 2), 16);
    }
    return out;
}

function u32BE(n: number): Uint8Array {
    const b = new Uint8Array(4);
    new DataView(b.buffer).setUint32(0, n >>> 0, false);
    return b;
}

function u64BE(n: bigint): Uint8Array {
    const b = new Uint8Array(8);
    new DataView(b.buffer).setBigUint64(0, n, false);
    return b;
}

function concat(parts: Uint8Array[]): Uint8Array {
    let len = 0;
    for (const p of parts) len += p.length;
    const out = new Uint8Array(len);
    let off = 0;
    for (const p of parts) { out.set(p, off); off += p.length; }
    return out;
}

export { toHex };

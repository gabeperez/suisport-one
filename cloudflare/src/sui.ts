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
import { ed25519 } from "@noble/curves/ed25519.js";
import { blake2b } from "@noble/hashes/blake2.js";

export interface SuiEnv {
    SUI_NETWORK?: string;
    SUI_PACKAGE_ID?: string;
    SUI_REWARDS_ENGINE_ID?: string;
    SUI_ORACLE_CAP_ID?: string;
    SUI_VERSION_OBJECT_ID?: string;
    SUI_OPERATOR_KEY?: string;
    ORACLE_PRIVATE_KEY?: string;
}

export function hasSuiConfig(env: SuiEnv): boolean {
    return !!(
        env.SUI_PACKAGE_ID &&
        env.SUI_REWARDS_ENGINE_ID &&
        env.SUI_ORACLE_CAP_ID &&
        env.SUI_VERSION_OBJECT_ID &&
        env.SUI_OPERATOR_KEY &&
        env.ORACLE_PRIVATE_KEY
    );
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
    oraclePrivateKeyB64: string,
    digest: Uint8Array
): Uint8Array {
    const raw = fromBase64(oraclePrivateKeyB64);
    // @mysten key export is 32-byte seed OR 64-byte keypair; handle both.
    const seed = raw.length === 32 ? raw : raw.slice(0, 32);
    return ed25519.sign(digest, seed);
}

/** Build + submit a `rewards_engine::submit_workout` transaction.
 *  Returns the executed tx digest (on success). Caller is responsible
 *  for ensuring hasSuiConfig(env) is true. */
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
    }
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

    const operator = Ed25519Keypair.fromSecretKey(
        fromBase64(env.SUI_OPERATOR_KEY!)
    );
    const res = await client.signAndExecuteTransaction({
        signer: operator,
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

/** Derive the operator's Sui address from the configured private key,
 *  useful for the status endpoint + setup scripts. */
export function operatorAddress(env: SuiEnv): string | null {
    if (!env.SUI_OPERATOR_KEY) return null;
    try {
        const kp = Ed25519Keypair.fromSecretKey(fromBase64(env.SUI_OPERATOR_KEY));
        return kp.getPublicKey().toSuiAddress();
    } catch {
        return null;
    }
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

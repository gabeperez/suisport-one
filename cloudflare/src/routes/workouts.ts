import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { workoutDTO, type WorkoutRow } from "../db.js";
import { requireAthlete } from "../auth.js";
import { parseBody, SubmitWorkoutSchema } from "../validation.js";
import { vetWorkout } from "../fraud.js";
import { walrusUploadSafe } from "../walrus.js";
import {
    hasSuiConfig, submitWorkoutOnChain, suiClient,
    operatorKeypairForAthlete, operatorKeypairByAddress,
} from "../sui.js";
import { Transaction } from "@mysten/sui/transactions";
import type { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

export const workouts = new Hono<{ Bindings: Env; Variables: Variables }>();

// Submit a workout.
//
// Pipeline (each stage no-ops gracefully when its env is missing):
//   1. Validate + fraud-vet
//   2. Persist to D1 (always — source of truth for the app UI)
//   3. Upload canonical workout JSON to Walrus → blobId
//   4. Ensure the athlete has an on-chain UserProfile (mint one if not)
//   5. Call rewards_engine::submit_workout via operator keypair
//   6. Record walrus_blob_id + sui_object_id + sui_tx_digest + sweat_minted
//
// Any non-blocking failure (Walrus 503, Sui RPC timeout) is logged and
// the workout still lands in D1 — we reconcile in the indexer.
workouts.post("/", async (c) => {
    const athleteId = requireAthlete(c);
    const body = await parseBody(c, SubmitWorkoutSchema);

    const vet = await vetWorkout(c.env, athleteId, body);
    if (!vet.ok) {
        return c.json({ error: "workout_rejected", reason: vet.reason }, 422);
    }

    const workoutId = `w_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;
    const feedId = `fi_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;
    const mapSeed = Math.floor(Math.random() * 1000);

    // 2. Persist immediately so the response returns fast + the feed
    //    updates even if the on-chain bits are slow.
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT INTO workouts (
                id, athlete_id, type, start_date, duration_seconds,
                distance_meters, energy_kcal, avg_heart_rate, pace_seconds_per_km,
                points, verified, is_demo, canonical_hash
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)`
        ).bind(
            workoutId, athleteId, body.type, body.startDate, body.durationSeconds,
            body.distanceMeters ?? null, body.energyKcal ?? null,
            body.avgHeartRate ?? null, body.paceSecondsPerKm ?? null,
            body.points, vet.canonicalHash
        ),
        c.env.DB.prepare(
            `INSERT INTO feed_items (id, athlete_id, workout_id, title, caption, map_preview_seed, is_demo)
             VALUES (?, ?, ?, ?, ?, ?, 0)`
        ).bind(
            feedId, athleteId, workoutId, body.title, body.caption ?? null, mapSeed
        ),
        c.env.DB.prepare(
            `UPDATE athletes SET total_workouts = total_workouts + 1 WHERE id = ?`
        ).bind(athleteId),
    ]);

    // 2.5 Trophies + personal records. Must run AFTER the INSERT into
    //      workouts so our lifetime/distance queries see this row, but
    //      BEFORE we respond — clients animate unlocks inline with the
    //      workout submission. Both are best-effort: failures log and
    //      swallow so a rewards-table outage can't block a save.
    try {
        await writeTrophyUnlocks(c.env, athleteId, {
            distanceMeters: body.distanceMeters ?? 0,
            points: body.points,
        });
    } catch (err) {
        console.warn("trophy_unlock_failed", err);
    }
    try {
        await writePersonalRecords(c.env, athleteId, workoutId, {
            startDate: body.startDate,
            distanceMeters: body.distanceMeters ?? 0,
            durationSeconds: body.durationSeconds,
            paceSecondsPerKm: body.paceSecondsPerKm ?? null,
        });
    } catch (err) {
        console.warn("pr_write_failed", err);
    }

    // 3. Walrus upload (canonical JSON representation).
    const canonical = JSON.stringify({
        athlete: athleteId,
        type: body.type,
        startDate: body.startDate,
        durationSeconds: body.durationSeconds,
        distanceMeters: body.distanceMeters,
        energyKcal: body.energyKcal,
        avgHeartRate: body.avgHeartRate,
        paceSecondsPerKm: body.paceSecondsPerKm,
        points: body.points,
        title: body.title,
        caption: body.caption,
    });
    const canonicalBytes = new TextEncoder().encode(canonical);
    const walrusResult = await walrusUploadSafe(c.env, canonicalBytes);

    if (walrusResult.blobId) {
        await c.env.DB.prepare(
            `UPDATE workouts SET walrus_blob_id = ? WHERE id = ?`
        ).bind(walrusResult.blobId, workoutId).run();
    }

    // 4–5. On-chain mint. Only if all the required config is set AND
    //      we have a Walrus blob id (the contract takes it as a param).
    let txDigest: string = `pending_${workoutId}`;
    let suiObjectId: string | null = null;
    let sweatMinted = 0;
    let pipelineStatus: string = "stubbed";

    if (hasSuiConfig(c.env) && walrusResult.blobId) {
        try {
            // Resolve the operator: if this athlete already has a
            // profile on-chain we MUST sign with the keypair that
            // owns it (stored in sui_user_profiles.operator_address).
            // First-time athletes get a hash-bucketed operator and
            // that address gets persisted during ensureUserProfile.
            const { operator, profileId } = await resolveOperatorAndProfile(c.env, athleteId);
            const rewardAmount = BigInt(body.points) * 1_000_000_000n; // 1 point = 1 SWEAT with 9 decimals
            const onChain = await submitWorkoutOnChain(c.env, {
                athlete: athleteId,
                profileObjectId: profileId,
                workoutType: workoutTypeCode(body.type),
                timestampMs: BigInt(body.startDate * 1000),
                durationS: Math.floor(body.durationSeconds),
                distanceM: Math.floor(body.distanceMeters ?? 0),
                calories: Math.floor(body.energyKcal ?? 0),
                walrusBlobId: new TextEncoder().encode(walrusResult.blobId),
                rewardAmount,
            }, operator);
            txDigest = onChain.txDigest;
            sweatMinted = Number(rewardAmount);
            pipelineStatus = "executed";
            await c.env.DB.prepare(
                `UPDATE workouts
                 SET sui_tx_digest = ?, verified = 1, sweat_minted = ?
                 WHERE id = ?`
            ).bind(txDigest, sweatMinted, workoutId).run();
        } catch (err) {
            // On-chain step failed; keep the workout in D1 with verified=0.
            // Indexer will NOT retry — user can resubmit if needed.
            pipelineStatus = `sui_failed:${err instanceof Error ? err.message : "unknown"}`;
        }
    } else if (!hasSuiConfig(c.env)) {
        pipelineStatus = "sui_not_configured";
    } else if (!walrusResult.blobId) {
        pipelineStatus = "walrus_upload_failed";
    }

    return c.json({
        workoutId,
        feedItemId: feedId,
        pointsMinted: body.points,
        txDigest,
        suiObjectId,
        walrusBlobId: walrusResult.blobId,
        attestation: { status: "accepted", pipeline: pipelineStatus },
    });
});

workouts.get("/:id", async (c) => {
    const row = await c.env.DB.prepare("SELECT * FROM workouts WHERE id = ?")
        .bind(c.req.param("id")).first<WorkoutRow>();
    if (!row) return c.json({ error: "not_found" }, 404);
    return c.json({ workout: workoutDTO(row) });
});

workouts.get("/:id/onchain", async (c) => {
    const row = await c.env.DB.prepare(
        `SELECT id, walrus_blob_id, sui_tx_digest, verified, sweat_minted
         FROM workouts WHERE id = ?`
    ).bind(c.req.param("id")).first<{
        id: string; walrus_blob_id: string | null;
        sui_tx_digest: string | null; verified: number;
        sweat_minted: number;
    }>();
    if (!row) return c.json({ error: "not_found" }, 404);
    const net = c.env.SUI_NETWORK || "testnet";
    const explorer = net === "mainnet"
        ? "https://suiscan.xyz/mainnet/tx"
        : "https://suiscan.xyz/testnet/tx";
    // Walrus viewer URL — testnet vs mainnet differ in path. Hardcoding
    // to testnet would break the in-app "View on Walrus" link the
    // moment we flip SUI_NETWORK to mainnet, so derive from the same
    // env var as the Sui explorer above.
    const walrusViewer = net === "mainnet"
        ? "https://walruscan.com/mainnet/blob"
        : "https://walruscan.com/testnet/blob";
    return c.json({
        workoutId: row.id,
        verified: row.verified === 1,
        walrusBlobId: row.walrus_blob_id,
        walrusUrl: row.walrus_blob_id ? `${walrusViewer}/${row.walrus_blob_id}` : null,
        txDigest: row.sui_tx_digest,
        txExplorerUrl: row.sui_tx_digest && !row.sui_tx_digest.startsWith("pending_")
            ? `${explorer}/${row.sui_tx_digest}` : null,
        sweatMinted: row.sweat_minted,
    });
});

// ---------- helpers ----------

/// Maps the iOS WorkoutType raw value to the u8 the Move contract
/// expects. Codes 0–7 are pre-pivot generic activities; 8–12 are
/// martial-arts categories added for the SuiSport ONE pivot. Keep
/// this table in sync with:
///   iHealth/Models/Workout.swift  (WorkoutType enum)
///   cloudflare/src/onchain_retry.ts (the retry-path mirror)
function workoutTypeCode(t: string): number {
    switch (t) {
        case "run":          return 0;
        case "walk":         return 1;
        case "ride":         return 2;
        case "hike":         return 3;
        case "swim":         return 4;
        case "lift":         return 5;
        case "yoga":         return 6;
        case "hiit":         return 7;
        case "striking":     return 8;
        case "grappling":    return 9;
        case "mma":          return 10;
        case "conditioning": return 11;
        case "recovery":     return 12;
        default:             return 255;
    }
}

/** Resolve the operator keypair + profile object id for an athlete.
 *
 *  Lookup order:
 *   1. If `sui_user_profiles` has a row, try to match its stored
 *      `operator_address` to a keypair in the pool — that's the
 *      signer that owns the profile on-chain.
 *   2. Fall back to the hash-bucketed mapping (legacy single-key
 *      deploys + rows created before operator_address was tracked).
 *   3. If no profile row exists yet, hash-bucket into the pool, mint
 *      a profile, and persist the operator address so subsequent
 *      submits always pick the same keypair regardless of later
 *      changes to SUI_OPERATOR_KEYS. */
export async function resolveOperatorAndProfile(
    env: Env,
    athleteId: string
): Promise<{ operator: Ed25519Keypair; profileId: string }> {
    const existing = await env.DB.prepare(
        `SELECT profile_object_id, operator_address
         FROM sui_user_profiles WHERE athlete_id = ?`
    ).bind(athleteId).first<{
        profile_object_id: string; operator_address: string | null;
    }>();
    if (existing) {
        if (existing.operator_address) {
            const kp = operatorKeypairByAddress(env, existing.operator_address);
            if (kp) return { operator: kp, profileId: existing.profile_object_id };
            // Fall through: the stored operator isn't in the pool
            // anymore (rotation). Try the hash path as last resort —
            // it likely won't work but we surface the ownership
            // error in the caller's try/catch rather than throwing
            // a different exception here.
        }
        return {
            operator: operatorKeypairForAthlete(env, athleteId),
            profileId: existing.profile_object_id,
        };
    }
    const operator = operatorKeypairForAthlete(env, athleteId);
    const profileId = await ensureUserProfile(env, athleteId, operator);
    return { operator, profileId };
}

/** Look up or lazily create a UserProfile object owned by the operator
 *  for this athlete. Per-user profiles in testnet let the operator
 *  submit on behalf of zkLogin addresses without asking the user to
 *  sign every time.
 *
 *  The operator parameter makes the caller responsible for picking
 *  the right keypair for this athlete — see operatorKeypairForAthlete
 *  in sui.ts. Exported so onchain_retry.ts can share the same mint
 *  path when it finds a pending workout without a profile. */
export async function ensureUserProfile(
    env: Env,
    athleteId: string,
    operator: Ed25519Keypair
): Promise<string> {
    const existing = await env.DB.prepare(
        `SELECT profile_object_id FROM sui_user_profiles WHERE athlete_id = ?`
    ).bind(athleteId).first<{ profile_object_id: string }>();
    if (existing) return existing.profile_object_id;

    // Mint a new profile via a user_profile::create_and_transfer call.
    // Operator pays; profile is transferred to sender (operator) so the
    // operator can mutate it later in submit_workout.
    const client = suiClient(env);
    const tx = new Transaction();
    tx.moveCall({
        target: `${env.SUI_PACKAGE_ID}::user_profile::create_and_transfer`,
        arguments: [],
    });
    const res = await client.signAndExecuteTransaction({
        signer: operator,
        transaction: tx,
        options: { showEffects: true, showObjectChanges: true },
    });
    const created = res.objectChanges?.find(
        (c: { type: string; objectType?: string }) =>
            c.type === "created" && c.objectType?.endsWith("::user_profile::UserProfile")
    ) as { objectId: string } | undefined;
    if (!created) throw new Error("profile_mint_failed");

    // Persist the signing operator so subsequent submits ALWAYS
    // target this keypair, even if the pool shifts. operator_address
    // was added in migration 0012; older envs without the column
    // will see an INSERT error here — the try/catch around the
    // caller swallows it and we silently proceed in single-key mode.
    const operatorAddr = operator.getPublicKey().toSuiAddress();
    await env.DB.prepare(
        `INSERT INTO sui_user_profiles
            (athlete_id, profile_object_id, created_tx_digest, operator_address)
         VALUES (?, ?, ?, ?)`
    ).bind(athleteId, created.objectId, res.digest, operatorAddr).run();
    return created.objectId;
}

// ---------- Trophies ----------

/// Writes trophy_unlocks rows for any trophy this workout earned. The
/// set of rules is hard-coded here (and seeded in migration 0012); we
/// intentionally don't pull rules from the DB because the logic
/// varies per trophy (distance vs streak vs points) and would end up
/// as a mini-DSL.
///
/// Idempotent via `INSERT OR IGNORE` on the (athlete_id, trophy_id)
/// PK — re-running for the same athlete + workout won't re-mint the
/// unlock. Progress is stored as 1.0 when earned; we don't currently
/// track partial progress from here (it'd require recomputing on
/// every workout, which the leaderboards + /me/trophies queries can
/// derive on read).
async function writeTrophyUnlocks(
    env: Env,
    athleteId: string,
    w: { distanceMeters: number; points: number }
): Promise<void> {
    const trophyIds: string[] = [];

    // First workout: athletes.total_workouts was just incremented to
    // 1 in the batch above this helper runs, so == 1 is the "this
    // was my first" signal.
    const aRow = await env.DB.prepare(
        `SELECT total_workouts FROM athletes WHERE id = ?`
    ).bind(athleteId).first<{ total_workouts: number }>();
    if ((aRow?.total_workouts ?? 0) === 1) {
        trophyIds.push("tro_first_run");
    }

    // Distance milestones — per-workout. Use this workout's distance,
    // not lifetime, since "First workout with >= 5km" is a different
    // achievement than "5km cumulative".
    if (w.distanceMeters >= 5_000)      trophyIds.push("tro_distance_5k");
    if (w.distanceMeters >= 10_000)     trophyIds.push("tro_distance_10k");
    if (w.distanceMeters >= 21_097.5)   trophyIds.push("tro_distance_half");
    if (w.distanceMeters >= 42_195)     trophyIds.push("tro_distance_full");

    // Streak milestones — derived from streaks.current_days written
    // elsewhere. Missing streak row = no unlocks.
    const streak = await env.DB.prepare(
        `SELECT current_days FROM streaks WHERE athlete_id = ?`
    ).bind(athleteId).first<{ current_days: number }>();
    const days = streak?.current_days ?? 0;
    if (days >= 7)   trophyIds.push("tro_streak_7");
    if (days >= 30)  trophyIds.push("tro_streak_30");
    if (days >= 100) trophyIds.push("tro_streak_100");

    // Lifetime points — uses sweat_points.total, which the streak /
    // points pipeline is expected to keep current. We look it up after
    // the workout insert so the value reflects this workout's points.
    // If the upstream pipeline hasn't written yet we still get the
    // value from the last known snapshot, which is acceptable —
    // users will see a 1-workout-lagged unlock, not a missed one
    // (we'll fire it next submission).
    const sp = await env.DB.prepare(
        `SELECT total FROM sweat_points WHERE athlete_id = ?`
    ).bind(athleteId).first<{ total: number }>();
    const total = sp?.total ?? 0;
    if (total >= 1_000)   trophyIds.push("tro_points_1k");
    if (total >= 10_000)  trophyIds.push("tro_points_10k");
    if (total >= 100_000) trophyIds.push("tro_points_100k");

    if (trophyIds.length === 0) return;
    const now = Math.floor(Date.now() / 1000);
    await env.DB.batch(trophyIds.map((tid) =>
        env.DB.prepare(
            `INSERT OR IGNORE INTO trophy_unlocks
                (athlete_id, trophy_id, progress, earned_at, is_demo)
             VALUES (?, ?, 1.0, ?, 0)`
        ).bind(athleteId, tid, now)
    ));
}

// ---------- Personal records ----------

/// Row shape + labels for the canonical distances we track. `meters`
/// is the exact distance a workout must cover (rounded to integer
/// meters); we use >= when matching candidate workouts so a 5.03km
/// run can count as a 5K PR. `label` matches the PRIMARY KEY used in
/// the `personal_records` table so `INSERT OR REPLACE` is safe.
const PR_DISTANCES: { label: string; meters: number }[] = [
    { label: "1K",   meters: 1_000 },
    { label: "5K",   meters: 5_000 },
    { label: "10K",  meters: 10_000 },
    { label: "Half", meters: 21_097 },
    { label: "Full", meters: 42_195 },
];

/// Recompute + update PRs for the athlete off a freshly-inserted
/// workout. We derive a "best time" for each target distance from
/// this workout alone — if the workout covered the distance and its
/// duration beats the existing row, we write a new PR.
///
/// Note: this only considers the single incoming workout. Historical
/// PR backfill is a separate admin job (workouts submitted before
/// the PR writer existed). Intentionally simple here because running
/// a full recompute per submit is too expensive for active users.
async function writePersonalRecords(
    env: Env,
    athleteId: string,
    workoutId: string,
    w: {
        startDate: number;
        distanceMeters: number;
        durationSeconds: number;
        paceSecondsPerKm: number | null;
    }
): Promise<void> {
    if (w.distanceMeters <= 0 || w.durationSeconds <= 0) return;

    // Existing PRs in one query, then we decide in TS. Avoids
    // sending 5 UPDATE-IF-BETTER conditionals through D1 individually.
    const existing = await env.DB.prepare(
        `SELECT label, best_time_seconds FROM personal_records WHERE athlete_id = ?`
    ).bind(athleteId).all<{ label: string; best_time_seconds: number | null }>();
    const bestByLabel = new Map<string, number | null>(
        (existing.results ?? []).map((r) => [r.label, r.best_time_seconds])
    );

    const stmts: D1PreparedStatement[] = [];
    for (const d of PR_DISTANCES) {
        if (w.distanceMeters < d.meters) continue;
        // Estimate "time to cover d.meters" from this workout. If the
        // workout is exactly the target distance, duration IS the PR
        // time. For longer workouts we scale by distance ratio under
        // the assumption of even pace — good enough for a server-
        // side PR detection without full split data. When pace is
        // explicit, prefer it since it's more accurate.
        const scaledSeconds = w.paceSecondsPerKm != null
            ? Math.round(w.paceSecondsPerKm * (d.meters / 1000))
            : Math.round(w.durationSeconds * (d.meters / w.distanceMeters));
        const prev = bestByLabel.get(d.label) ?? null;
        const isBetter = prev == null || scaledSeconds < prev;
        if (!isBetter) continue;
        stmts.push(env.DB.prepare(
            // PK is (athlete_id, label). On conflict, update the
            // time + achieved_at + workout_id in-place.
            `INSERT INTO personal_records
                (athlete_id, label, distance_meters, best_time_seconds,
                 achieved_at, workout_id, is_demo)
             VALUES (?, ?, ?, ?, ?, ?, 0)
             ON CONFLICT(athlete_id, label) DO UPDATE SET
                best_time_seconds = excluded.best_time_seconds,
                achieved_at       = excluded.achieved_at,
                workout_id        = excluded.workout_id`
        ).bind(
            athleteId, d.label, d.meters, scaledSeconds,
            w.startDate, workoutId
        ));
    }
    if (stmts.length > 0) await env.DB.batch(stmts);
}

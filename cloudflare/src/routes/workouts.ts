import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { workoutDTO, type WorkoutRow } from "../db.js";
import { requireAthlete } from "../auth.js";
import { parseBody, SubmitWorkoutSchema } from "../validation.js";
import { vetWorkout } from "../fraud.js";
import { walrusUploadSafe } from "../walrus.js";
import { hasSuiConfig, submitWorkoutOnChain, suiClient, operatorKeypair } from "../sui.js";
import { Transaction } from "@mysten/sui/transactions";

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
            const profileId = await ensureUserProfile(c.env, athleteId);
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
            });
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
    const walrusViewer = "https://walruscan.com/testnet/blob";
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

function workoutTypeCode(t: string): number {
    // Contract uses u8 codes matching the Move enum ordering.
    switch (t) {
        case "run":  return 0;
        case "walk": return 1;
        case "ride": return 2;
        case "hike": return 3;
        case "swim": return 4;
        case "lift": return 5;
        case "yoga": return 6;
        case "hiit": return 7;
        default:     return 255;
    }
}

/** Look up or lazily create a UserProfile object owned by the operator
 *  for this athlete. Per-user profiles in testnet let the operator
 *  submit on behalf of zkLogin addresses without asking the user to
 *  sign every time. */
async function ensureUserProfile(env: Env, athleteId: string): Promise<string> {
    const existing = await env.DB.prepare(
        `SELECT profile_object_id FROM sui_user_profiles WHERE athlete_id = ?`
    ).bind(athleteId).first<{ profile_object_id: string }>();
    if (existing) return existing.profile_object_id;

    // Mint a new profile via a user_profile::create_and_transfer call.
    // Operator pays; profile is transferred to sender (operator) so the
    // operator can mutate it later in submit_workout.
    const client = suiClient(env);
    const operator = operatorKeypair(env.SUI_OPERATOR_KEY!);
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

    await env.DB.prepare(
        `INSERT INTO sui_user_profiles (athlete_id, profile_object_id, created_tx_digest)
         VALUES (?, ?, ?)`
    ).bind(athleteId, created.objectId, res.digest).run();
    return created.objectId;
}

// Reconciler for workouts whose on-chain submit failed at POST time.
//
// When a workout lands in D1 with `sui_tx_digest LIKE 'pending_%'`,
// either:
//   (a) the operator RPC call timed out,
//   (b) the operator key was out of gas,
//   (c) we hit a version-object contention error under concurrency,
//   (d) Sui testnet itself was flaky,
// none of which are fatal. The workout is real; we just haven't
// minted the SWEAT reward yet.
//
// This reconciler runs from the same scheduled() handler as the
// event indexer. Each tick:
//   1. Select up to MAX_PER_TICK pending workouts ordered by
//      (onchain_retry_count, onchain_last_retry_at, created_at)
//      — so we always try the least-retried + oldest first.
//   2. For each, load the walrus blob id + body params from the row.
//   3. Call submitWorkoutOnChain exactly as the POST path does.
//   4. On success, stamp sui_tx_digest + verified=1 + sweat_minted.
//      On failure, increment retry_count + stash the error.
//
// Throughput is capped at MAX_PER_TICK per minute (one tick = one
// minute in wrangler.toml). The operator keypair can comfortably do
// that sequentially; no fanout needed at current testnet scale.
//
// Hard ceiling: after MAX_RETRIES attempts we stop retrying and
// surface the workout in the admin dashboard for manual review.

import type { Env } from "./env.js";
import {
    hasSuiConfig,
    submitWorkoutOnChain,
} from "./sui.js";
import { resolveOperatorAndProfile } from "./routes/workouts.js";
import {
    deriveFormulaComponents, computeFinalReward,
} from "./sweat_formula.js";

const MAX_PER_TICK = 20;
const MAX_RETRIES = 10;
const BACKOFF_MIN_SECONDS = 60;
const BACKOFF_BASE_SECONDS = 120;

interface PendingRow {
    id: string;
    athlete_id: string;
    type: string;
    start_date: number;
    duration_seconds: number;
    distance_meters: number | null;
    energy_kcal: number | null;
    points: number;
    walrus_blob_id: string | null;
    onchain_retry_count: number;
    onchain_last_retry_at: number | null;
}

export interface RetryTickResult {
    ok: boolean;
    attempted: number;
    succeeded: number;
    failed: number;
    skipped_no_walrus: number;
    error?: string;
}

export async function retryPendingWorkoutsTick(env: Env): Promise<RetryTickResult> {
    if (!hasSuiConfig(env)) {
        return { ok: true, attempted: 0, succeeded: 0, failed: 0, skipped_no_walrus: 0 };
    }

    const now = Math.floor(Date.now() / 1000);
    // Backoff: don't retry rows that were last tried less than
    // BACKOFF_MIN_SECONDS * 2^retry_count ago.
    const rows = await env.DB.prepare(
        `SELECT id, athlete_id, type, start_date, duration_seconds,
                distance_meters, energy_kcal, points, walrus_blob_id,
                onchain_retry_count, onchain_last_retry_at
         FROM workouts
         WHERE sui_tx_digest LIKE 'pending_%'
           AND onchain_retry_count < ?
           AND (onchain_last_retry_at IS NULL
             OR (? - onchain_last_retry_at) >
                (? + ? * onchain_retry_count * onchain_retry_count))
         ORDER BY onchain_retry_count ASC, onchain_last_retry_at ASC, created_at ASC
         LIMIT ?`
    ).bind(
        MAX_RETRIES, now, BACKOFF_MIN_SECONDS, BACKOFF_BASE_SECONDS, MAX_PER_TICK
    ).all<PendingRow>();

    let succeeded = 0;
    let failed = 0;
    let skipped_no_walrus = 0;

    for (const row of rows.results ?? []) {
        if (!row.walrus_blob_id) {
            // Without a blob id the contract rejects the call. Skip —
            // the media upload retry is a separate concern.
            skipped_no_walrus++;
            continue;
        }
        try {
            // Share the same resolver as the POST path. If the
            // profile was never minted (POST failed before the mint
            // call completed) this MINTS it here — that's the fix
            // for the silent-stall bug where we used to skip rows
            // with no profile. After minting we can submit the
            // workout in the same tick.
            const { operator, profileId } = await resolveOperatorAndProfile(
                env, row.athlete_id
            );
            // Reconciler doesn't have access to PR / challenge state at
            // the original submit time, so it conservatively flags
            // those as false. The athlete still gets the base + decay
            // + streak components — those derive from current D1.
            const components = await deriveFormulaComponents(env, {
                baseSweatPoints: row.points,
                workoutType: row.type,
                athleteId: row.athlete_id,
                isPersonalRecord: false,
                isChallengeContribution: false,
            });
            const finalReward = computeFinalReward(components);
            const onChain = await submitWorkoutOnChain(env, {
                athlete: row.athlete_id,
                profileObjectId: profileId,
                workoutType: workoutTypeCode(row.type),
                timestampMs: BigInt(row.start_date * 1000),
                durationS: Math.floor(row.duration_seconds),
                distanceM: Math.floor(row.distance_meters ?? 0),
                calories: Math.floor(row.energy_kcal ?? 0),
                walrusBlobId: new TextEncoder().encode(row.walrus_blob_id),
                baseReward: components.baseReward,
                prBonus: components.prBonus,
                challengeBonus: components.challengeBonus,
                firstTimeBonus: components.firstTimeBonus,
                streakDays: components.streakDays,
                repetitionDecayBps: components.repetitionDecayBps,
            }, operator);
            await env.DB.prepare(
                `UPDATE workouts
                 SET sui_tx_digest = ?, verified = 1, sweat_minted = ?,
                     onchain_last_retry_at = ?, onchain_last_error = NULL
                 WHERE id = ?`
            ).bind(
                onChain.txDigest, Number(finalReward), now, row.id
            ).run();
            succeeded++;
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            await env.DB.prepare(
                `UPDATE workouts
                 SET onchain_retry_count = onchain_retry_count + 1,
                     onchain_last_retry_at = ?, onchain_last_error = ?
                 WHERE id = ?`
            ).bind(now, msg.slice(0, 500), row.id).run();
            failed++;
        }
    }

    return {
        ok: true,
        attempted: rows.results?.length ?? 0,
        succeeded, failed, skipped_no_walrus,
    };
}

/// Mirror of routes/workouts.ts:workoutTypeCode. Keep both tables
/// in lockstep — divergence means the reconciler retries with a
/// different u8 than the user's original POST and breaks the
/// canonical workout digest.
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

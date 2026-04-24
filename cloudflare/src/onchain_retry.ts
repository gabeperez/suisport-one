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
            const profileId = await lookupProfileId(env, row.athlete_id);
            if (!profileId) {
                // Still no profile minted; the submit path will retry
                // next time the user submits. Leave alone.
                continue;
            }
            const rewardAmount = BigInt(row.points) * 1_000_000_000n;
            const onChain = await submitWorkoutOnChain(env, {
                athlete: row.athlete_id,
                profileObjectId: profileId,
                workoutType: workoutTypeCode(row.type),
                timestampMs: BigInt(row.start_date * 1000),
                durationS: Math.floor(row.duration_seconds),
                distanceM: Math.floor(row.distance_meters ?? 0),
                calories: Math.floor(row.energy_kcal ?? 0),
                walrusBlobId: new TextEncoder().encode(row.walrus_blob_id),
                rewardAmount,
            });
            await env.DB.prepare(
                `UPDATE workouts
                 SET sui_tx_digest = ?, verified = 1, sweat_minted = ?,
                     onchain_last_retry_at = ?, onchain_last_error = NULL
                 WHERE id = ?`
            ).bind(
                onChain.txDigest, Number(rewardAmount), now, row.id
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

async function lookupProfileId(env: Env, athleteId: string): Promise<string | null> {
    const row = await env.DB.prepare(
        `SELECT profile_object_id FROM sui_user_profiles WHERE athlete_id = ?`
    ).bind(athleteId).first<{ profile_object_id: string }>();
    return row?.profile_object_id ?? null;
}

function workoutTypeCode(t: string): number {
    switch (t) {
        case "run":  return 0;
        case "walk": return 1;
        case "ride": return 2;
        case "hike": return 3;
        case "swim": return 4;
        default:      return 5;
    }
}

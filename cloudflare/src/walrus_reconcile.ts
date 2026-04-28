// Walrus blob reconciler — companion to the Walrus-optional path in
// `routes/workouts.ts`.
//
// When Walrus testnet 503s during a workout submit, we still mint to
// Sui (so the user gets their Sweat + soulbound Workout NFT), but the
// canonical workout JSON never lands on Walrus and the workout's
// `walrus_blob_id` column stays NULL in D1.
//
// This tick sweeps NULL rows on a serial cron, retries the upload, and
// patches D1 once Walrus comes back. iOS reads `walrusBlobId` from the
// workout DTO — when D1's value flips from NULL to a real id, the
// "Permanent record" deep link in the app starts resolving without
// requiring the user to do anything.
//
// Scope intentionally limited:
//   - On-chain Workout NFT keeps its `walrus_pending_<workoutId>`
//     placeholder forever. Patching the on-chain bytes would require
//     a Move package upgrade and a new `patch_walrus_blob` entry —
//     spec'd in docs/WALRUS_RECONCILE.md (v2 work).
//   - LIMIT 25 per tick keeps the reconciler bounded if Walrus stays
//     down for an extended window.

import type { Env } from "./env.js";
import { walrusUploadSafe } from "./walrus.js";

interface PendingRow {
    id: string;
    athlete_id: string;
    type: string;
    start_date: number;
    duration_seconds: number;
    distance_meters: number | null;
    energy_kcal: number | null;
    avg_heart_rate: number | null;
    pace_seconds_per_km: number | null;
    points: number;
    title: string | null;
    caption: string | null;
}

export async function reconcileWalrusPendingTick(
    env: Env
): Promise<{ attempted: number; succeeded: number; failed: number }> {
    const result = { attempted: 0, succeeded: 0, failed: 0 };

    const rows = await env.DB.prepare(`
        SELECT w.id, w.athlete_id, w.type, w.start_date,
               w.duration_seconds, w.distance_meters, w.energy_kcal,
               w.avg_heart_rate, w.pace_seconds_per_km, w.points,
               fi.title, fi.caption
        FROM workouts w
        LEFT JOIN feed_items fi ON fi.workout_id = w.id
        WHERE w.walrus_blob_id IS NULL
          AND w.verified = 1
        ORDER BY w.created_at ASC
        LIMIT 25
    `).all<PendingRow>();

    for (const row of rows.results ?? []) {
        result.attempted++;
        // Match the inline canonical shape from routes/workouts.ts.
        // Keep this in sync if either side changes — but the reconciler
        // only powers the iOS "Permanent record" link, not the chain
        // attestation_hash, so a small shape drift is recoverable.
        const canonical = JSON.stringify({
            athlete: row.athlete_id,
            type: row.type,
            startDate: row.start_date,
            durationSeconds: row.duration_seconds,
            distanceMeters: row.distance_meters,
            energyKcal: row.energy_kcal,
            avgHeartRate: row.avg_heart_rate,
            paceSecondsPerKm: row.pace_seconds_per_km,
            points: row.points,
            title: row.title ?? "",
            caption: row.caption,
        });
        const upload = await walrusUploadSafe(
            env, new TextEncoder().encode(canonical)
        );
        if (upload.blobId) {
            await env.DB.prepare(
                `UPDATE workouts SET walrus_blob_id = ? WHERE id = ?`
            ).bind(upload.blobId, row.id).run();
            result.succeeded++;
        } else {
            result.failed++;
        }
    }

    return result;
}

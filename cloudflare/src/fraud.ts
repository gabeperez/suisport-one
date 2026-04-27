import type { Env } from "./env.js";

// Baseline anti-fraud checks for workout submissions.
//
// None of these are "proof" the workout is real — only App Attest + Sui
// attestation can do that. These are pre-attestation sanity gates that
// reject obviously-bogus payloads before they pollute the feed.

const MAX_WORKOUTS_PER_DAY = 20;

// Top-end pace thresholds. Any submission faster than this is rejected
// outright — beyond current world-record territory, so only a bug or
// fraud could produce it. Values are seconds per kilometer.
const WORLD_RECORD_PACE_SEC_PER_KM: Record<string, number> = {
    run: 150,      // 2:30/km is ~ men's mile WR pace (Hicham El Guerrouj)
    walk: 300,     // 5:00/km is elite racewalk
    ride: 45,      // 45s/km = 80 km/h sustained
    hike: 300,     // 5:00/km is very fast hike / trail run
};

export interface WorkoutPayload {
    type: string;
    startDate: number;
    durationSeconds: number;
    distanceMeters?: number | null;
    energyKcal?: number | null;
    avgHeartRate?: number | null;
    points: number;
}

export async function canonicalHash(
    athleteId: string,
    w: WorkoutPayload
): Promise<string> {
    // Canonicalize the fields that identify "the same workout":
    // athlete + start minute + duration minute + distance (10m bucket)
    // + type + energy (25-kcal bucket) + avg HR (5-bpm bucket).
    //
    // The energy + heart-rate buckets protect against the theoretical
    // minute-granularity collision: two distinct workouts starting in
    // the same minute with identical duration + distance still have
    // different calorie burn + HR signatures in practice, so they
    // won't hash to the same value. Bucket sizes are coarse enough to
    // tolerate sensor jitter on genuine re-uploads of the same run.
    const minute = Math.floor(w.startDate / 60);
    const durMin = Math.round(w.durationSeconds / 60);
    const distBucket = w.distanceMeters != null
        ? Math.round(w.distanceMeters / 10) * 10
        : 0;
    const kcalBucket = w.energyKcal != null
        ? Math.round(w.energyKcal / 25) * 25
        : 0;
    const hrBucket = w.avgHeartRate != null
        ? Math.round(w.avgHeartRate / 5) * 5
        : 0;
    const canonical = `${athleteId}|${w.type}|${minute}|${durMin}|${distBucket}|${kcalBucket}|${hrBucket}`;
    const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
    return [...new Uint8Array(buf)]
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
}

export async function vetWorkout(
    env: Env,
    athleteId: string,
    w: WorkoutPayload
): Promise<{ ok: true; canonicalHash: string } | { ok: false; reason: string }> {
    // 1. Velocity: more than 20 in last 24h is suspicious.
    const recentCount = await env.DB.prepare(
        `SELECT COUNT(*) AS n FROM workouts
         WHERE athlete_id = ? AND start_date > ?`
    ).bind(athleteId, Math.floor(Date.now() / 1000) - 86400)
        .first<{ n: number }>();
    if ((recentCount?.n ?? 0) >= MAX_WORKOUTS_PER_DAY) {
        await logSuspect(env, athleteId, "velocity_exceeded", w);
        return { ok: false, reason: "velocity_exceeded" };
    }

    // 2. Duration sanity.
    if (w.durationSeconds < 60) {
        return { ok: false, reason: "duration_too_short" };
    }
    if (w.durationSeconds > 24 * 3600) {
        return { ok: false, reason: "duration_too_long" };
    }

    // 3. Pace sanity (only when distance is present).
    if (w.distanceMeters && w.distanceMeters > 0) {
        const paceSecPerKm = w.durationSeconds / (w.distanceMeters / 1000);
        const threshold = WORLD_RECORD_PACE_SEC_PER_KM[w.type];
        if (threshold && paceSecPerKm < threshold) {
            await logSuspect(env, athleteId, "pace_impossible", { ...w, paceSecPerKm });
            return { ok: false, reason: "pace_impossible" };
        }
    }

    // 4. Points sanity. Loose cap that accommodates the iOS
    //    `SweatPoints.forWorkout` rates (e.g. ride = 60 pts/km +
    //    2 pts/min — a 30 km ride in 90 min legitimately scores
    //    ~22 pts/min). The cap is still here to reject obviously
    //    fake claims (1 min = 1,000,000 points), but it no longer
    //    blocks normal high-volume workouts. The on-chain mint
    //    amount is recomputed server-side from the validated
    //    duration + distance regardless, so this cap doesn't gate
    //    what actually mints — it only gates what gets accepted
    //    into the feed at all.
    const maxPointsByMinute = 30;
    const cap = Math.ceil(w.durationSeconds / 60) * maxPointsByMinute;
    if (w.points > cap) {
        await logSuspect(env, athleteId, "points_inflated",
            { claimed: w.points, cap, durationSeconds: w.durationSeconds });
        return { ok: false, reason: "points_inflated" };
    }

    // 5. Dedup via canonical hash. Actual UNIQUE constraint failure is
    // caught by the caller as a D1 constraint error; we compute + return
    // the hash here so the caller can bind it on INSERT.
    const hash = await canonicalHash(athleteId, w);
    const dup = await env.DB.prepare(
        `SELECT 1 FROM workouts WHERE athlete_id = ? AND canonical_hash = ?`
    ).bind(athleteId, hash).first();
    if (dup) {
        await logSuspect(env, athleteId, "duplicate_submission", w);
        return { ok: false, reason: "duplicate" };
    }

    return { ok: true, canonicalHash: hash };
}

async function logSuspect(
    env: Env,
    athleteId: string,
    reason: string,
    details: unknown
): Promise<void> {
    await env.DB.prepare(
        `INSERT INTO suspect_activity (id, athlete_id, reason, details)
         VALUES (?, ?, ?, ?)`
    ).bind(
        crypto.randomUUID(), athleteId, reason, JSON.stringify(details)
    ).run();
}

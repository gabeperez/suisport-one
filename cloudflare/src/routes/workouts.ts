import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { workoutDTO, type WorkoutRow } from "../db.js";
import { requireAthlete } from "../auth.js";

export const workouts = new Hono<{ Bindings: Env; Variables: Variables }>();

// Submit a workout. Creates a workout + feed_item in one batch. The
// attestation pipeline (App Attest → canonical hash → Walrus → Sui PTB)
// is stubbed for now — we accept and persist, returning a placeholder
// tx digest. Promote to Queues when the real pipeline lands.
workouts.post("/", async (c) => {
    const athleteId = requireAthlete(c);
    const body = await c.req.json<{
        type: string;
        startDate: number;
        durationSeconds: number;
        distanceMeters?: number | null;
        energyKcal?: number | null;
        avgHeartRate?: number | null;
        paceSecondsPerKm?: number | null;
        points: number;
        title: string;
        caption?: string | null;
    }>();

    const workoutId = `w_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;
    const feedId = `fi_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;
    const mapSeed = Math.floor(Math.random() * 1000);

    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT INTO workouts (
                id, athlete_id, type, start_date, duration_seconds,
                distance_meters, energy_kcal, avg_heart_rate, pace_seconds_per_km,
                points, verified, is_demo
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)`
        ).bind(
            workoutId, athleteId, body.type, body.startDate, body.durationSeconds,
            body.distanceMeters ?? null, body.energyKcal ?? null,
            body.avgHeartRate ?? null, body.paceSecondsPerKm ?? null,
            body.points
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

    // Stub attestation pipeline: returns placeholder txDigest.
    // TODO: enqueue to Cloudflare Queue for Walrus upload + Sui PTB.
    return c.json({
        workoutId,
        feedItemId: feedId,
        pointsMinted: body.points,
        txDigest: `pending_${workoutId}`,
        attestation: { status: "accepted", pipeline: "stubbed" },
    });
});

workouts.get("/:id", async (c) => {
    const row = await c.env.DB.prepare("SELECT * FROM workouts WHERE id = ?")
        .bind(c.req.param("id")).first<WorkoutRow>();
    if (!row) return c.json({ error: "not_found" }, 404);
    return c.json({ workout: workoutDTO(row) });
});

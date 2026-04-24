import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { requireAthlete } from "../auth.js";

export const account = new Hono<{ Bindings: Env; Variables: Variables }>();

// GDPR Article 20 — right to data portability. Returns a JSON document
// of every row belonging to the caller, across all tables. Users can
// share the file, forward it to themselves, or audit the service.
account.get("/me/export", async (c) => {
    const id = requireAthlete(c);

    const [
        athlete, user, feedItems, workouts, kudos, comments, follows,
        mutes, reports, clubMemberships, clubsOwned, challengeParticipations,
        segmentEfforts, segmentStars, trophyUnlocks, shoes, personalRecords,
        streaks, sweat, sessions, attestKeys,
    ] = await Promise.all([
        q(c, "SELECT * FROM athletes WHERE id = ?", [id]),
        q(c, "SELECT * FROM users WHERE sui_address = ?", [id]),
        q(c, "SELECT * FROM feed_items WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM workouts WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM kudos WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM comments WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM follows WHERE follower_id = ? OR followee_id = ?", [id, id]),
        q(c, "SELECT * FROM mutes WHERE muter_id = ?", [id]),
        q(c, "SELECT * FROM reports WHERE reporter_id = ?", [id]),
        q(c, "SELECT * FROM club_members WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM clubs WHERE owner_athlete_id = ?", [id]),
        q(c, "SELECT * FROM challenge_participants WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM segment_efforts WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM segment_stars WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM trophy_unlocks WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM shoes WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM personal_records WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM streaks WHERE athlete_id = ?", [id]),
        q(c, "SELECT * FROM sweat_points WHERE athlete_id = ?", [id]),
        q(c, "SELECT id, created_at, expires_at FROM sessions WHERE sui_address = ?", [id]),
        q(c, "SELECT key_id, counter, registered_at FROM app_attest_keys WHERE athlete_id = ?", [id]),
    ]);

    return c.json({
        exportedAt: Date.now(),
        exportFormat: "suisport-user-export/1",
        athleteId: id,
        data: {
            athlete, user, feedItems, workouts, kudos, comments, follows,
            mutes, reports, clubMemberships, clubsOwned, challengeParticipations,
            segmentEfforts, segmentStars, trophyUnlocks, shoes, personalRecords,
            streaks, sweat, sessions, attestKeys,
        },
    }, 200, {
        "Content-Disposition": `attachment; filename="suisport-export-${id}.json"`,
    });
});

// GDPR Article 17 — right to erasure. Hard-deletes the athlete row,
// cascading through every is-foreign-key-to-athlete table. R2 objects
// owned by the user are enumerated and purged. Sessions invalidated.
account.delete("/me", async (c) => {
    const id = requireAthlete(c);

    // Pull R2 keys we need to wipe BEFORE deleting the rows that
    // reference them.
    const photos = await q(c, "SELECT photo_r2_key FROM athletes WHERE id = ? AND photo_r2_key IS NOT NULL", [id]);
    const banners = await q(c, "SELECT banner_r2_key FROM clubs WHERE owner_athlete_id = ? AND banner_r2_key IS NOT NULL", [id]);
    const allR2Keys = [
        ...photos.map((p) => (p as { photo_r2_key: string | null }).photo_r2_key),
        ...banners.map((p) => (p as { banner_r2_key: string | null }).banner_r2_key),
    ].filter((k): k is string => !!k);

    // Delete sessions + the athlete row. Foreign-key cascades handle
    // the rest (feed_items, workouts, kudos, comments, club_members,
    // challenge_participants, segment_efforts, shoes, PRs, streaks,
    // trophy_unlocks, follows, mutes, attestation keys, challenges).
    await c.env.DB.batch([
        c.env.DB.prepare(`DELETE FROM sessions WHERE sui_address = ?`).bind(id),
        c.env.DB.prepare(`DELETE FROM athletes WHERE id = ?`).bind(id),
        c.env.DB.prepare(`DELETE FROM users WHERE sui_address = ?`).bind(id),
    ]);

    // Best-effort R2 cleanup.
    for (const key of allR2Keys) {
        await c.env.MEDIA.delete(key).catch(() => {});
    }

    // NOTE: on-chain data (Sui objects, Walrus blobs) can't be deleted.
    // They're publicly pseudonymous; the user retains the Sui key and
    // can burn / transfer if desired. This is documented in the
    // privacy policy.
    return c.json({
        ok: true,
        note: "Server-side data deleted. On-chain data (Sui + Walrus) remains — see privacy policy.",
    }, 200);
});

async function q(
    c: { env: Env },
    sql: string,
    binds: unknown[]
): Promise<Record<string, unknown>[]> {
    const res = await c.env.DB.prepare(sql).bind(...binds).all<Record<string, unknown>>();
    return res.results ?? [];
}

// ---------------------------------------------------------------------
// Push token registration.
//
// iOS calls this immediately after `didRegisterForRemoteNotifications`
// returns. Token rotates on reinstall / restore-from-backup, so we
// upsert on the token as primary key. A single athlete may have
// multiple rows (iPhone + iPad).
// ---------------------------------------------------------------------
account.post("/account/push-token", async (c) => {
    const id = requireAthlete(c);
    const body = await c.req.json<{ token: string; env?: string }>().catch(() => null);
    if (!body?.token || !/^[0-9a-f]{32,200}$/i.test(body.token)) {
        return c.json({ error: "bad_token" }, 400);
    }
    const env = body.env === "sandbox" ? "sandbox" : "production";
    await c.env.DB.prepare(
        `INSERT INTO push_tokens (token, athlete_id, platform, env, updated_at, disabled_at)
         VALUES (?, ?, 'ios', ?, unixepoch(), NULL)
         ON CONFLICT(token) DO UPDATE SET
           athlete_id = excluded.athlete_id,
           env        = excluded.env,
           updated_at = unixepoch(),
           disabled_at = NULL,
           last_error = NULL,
           last_error_at = NULL`
    ).bind(body.token, id, env).run();
    return c.json({ ok: true });
});

account.delete("/account/push-token", async (c) => {
    const id = requireAthlete(c);
    const body = await c.req.json<{ token?: string }>().catch(() => ({} as { token?: string }));
    if (body.token) {
        await c.env.DB.prepare(
            `DELETE FROM push_tokens WHERE token = ? AND athlete_id = ?`
        ).bind(body.token, id).run();
    } else {
        await c.env.DB.prepare(
            `DELETE FROM push_tokens WHERE athlete_id = ?`
        ).bind(id).run();
    }
    return c.json({ ok: true });
});

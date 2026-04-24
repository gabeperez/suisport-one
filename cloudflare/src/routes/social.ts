import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import {
    athleteDTO, feedItemDTO, workoutDTO, clubDTO, challengeDTO,
    segmentDTO, trophyDTO, shoeDTO, prDTO,
    type AthleteRow, type WorkoutRow, type FeedItemRow,
    type ClubRow, type ChallengeRow, type SegmentRow,
    type TrophyRow, type ShoeRow, type PRRow,
} from "../db.js";
import { requireAthlete } from "../auth.js";
import { resolveInternalId } from "../identity.js";
import {
    parseBody, AthletePatchSchema, KudosSchema, CommentSchema,
    ReportSchema, CreateClubSchema, AddShoeSchema,
} from "../validation.js";

export const social = new Hono<{ Bindings: Env; Variables: Variables }>();

// ---------- Athletes ----------

social.get("/athletes", async (c) => {
    const rows = await c.env.DB.prepare(
        `SELECT * FROM athletes
         WHERE suspended_at IS NULL
         ORDER BY total_workouts DESC LIMIT 200`
    ).all<AthleteRow>();
    return c.json({ athletes: rows.results.map(athleteDTO) });
});

social.get("/athletes/:id", async (c) => {
    const id = c.req.param("id");
    const row = await c.env.DB.prepare(
        "SELECT * FROM athletes WHERE user_id = ? OR id = ? LIMIT 1"
    ).bind(id, id).first<AthleteRow>();
    if (!row) return c.json({ error: "not_found" }, 404);
    return c.json({ athlete: athleteDTO(row) });
});

social.get("/me", async (c) => {
    const id = c.get("athleteId") ?? "0xdemo_me";
    const row = await c.env.DB.prepare("SELECT * FROM athletes WHERE id = ?")
        .bind(id).first<AthleteRow>();
    if (!row) return c.json({ error: "not_found" }, 404);
    return c.json({ athlete: athleteDTO(row) });
});

social.patch("/me", async (c) => {
    const id = requireAthlete(c);
    const body = await parseBody(c, AthletePatchSchema);
    const fields: string[] = [];
    const binds: unknown[] = [];
    if (body.displayName != null) { fields.push("display_name = ?"); binds.push(body.displayName); }
    if (body.handle != null) { fields.push("handle = ?"); binds.push(body.handle); }
    if (body.bio !== undefined) { fields.push("bio = ?"); binds.push(body.bio); }
    if (body.location !== undefined) { fields.push("location = ?"); binds.push(body.location); }
    if (body.avatarTone != null) { fields.push("avatar_tone = ?"); binds.push(body.avatarTone); }
    if (body.bannerTone != null) { fields.push("banner_tone = ?"); binds.push(body.bannerTone); }
    if (body.photoR2Key !== undefined) { fields.push("photo_r2_key = ?"); binds.push(body.photoR2Key); }
    if (body.dob != null) { fields.push("dob = ?"); binds.push(body.dob); }
    if (!fields.length) return c.json({ ok: true });
    fields.push("updated_at = unixepoch()");
    binds.push(id);
    await c.env.DB.prepare(`UPDATE athletes SET ${fields.join(", ")} WHERE id = ?`).bind(...binds).run();
    const updated = await c.env.DB.prepare("SELECT * FROM athletes WHERE id = ?")
        .bind(id).first<AthleteRow>();
    return c.json({ athlete: updated ? athleteDTO(updated) : null });
});

// ---------- Feed ----------

social.get("/feed", async (c) => {
    const sort = c.req.query("sort") ?? "recent";
    const limit = Math.min(parseInt(c.req.query("limit") ?? "50", 10), 200);
    const order = sort === "kudos"
        ? "fi.kudos_count DESC, fi.created_at DESC"
        : "w.start_date DESC";
    const rows = await c.env.DB.prepare(
        `SELECT fi.*, a.id AS _a_id, w.id AS _w_id FROM feed_items fi
         JOIN athletes a ON a.id = fi.athlete_id
         JOIN workouts w ON w.id = fi.workout_id
         WHERE a.suspended_at IS NULL
         ORDER BY ${order} LIMIT ?`
    ).bind(limit).all<FeedItemRow & { _a_id: string; _w_id: string }>();

    // Batch-fetch athletes + workouts referenced in the feed slice.
    const aIds = [...new Set(rows.results.map((r) => r.athlete_id))];
    const wIds = [...new Set(rows.results.map((r) => r.workout_id))];
    const athletes = aIds.length
        ? await c.env.DB.prepare(
            `SELECT * FROM athletes WHERE id IN (${aIds.map(() => "?").join(",")})`
          ).bind(...aIds).all<AthleteRow>()
        : { results: [] as AthleteRow[] };
    const workouts = wIds.length
        ? await c.env.DB.prepare(
            `SELECT * FROM workouts WHERE id IN (${wIds.map(() => "?").join(",")})`
          ).bind(...wIds).all<WorkoutRow>()
        : { results: [] as WorkoutRow[] };
    const aById = new Map(athletes.results.map((r) => [r.id, r]));
    const wById = new Map(workouts.results.map((r) => [r.id, r]));

    const items = rows.results
        .map((r) => {
            const a = aById.get(r.athlete_id);
            const w = wById.get(r.workout_id);
            return a && w ? feedItemDTO(r, a, w) : null;
        })
        .filter(Boolean);
    return c.json({ items });
});

// ---------- Kudos + comments ----------

social.post("/feed/:id/kudos", async (c) => {
    const athleteId = requireAthlete(c);
    const feedItemId = c.req.param("id");
    const body = await parseBody(c, KudosSchema);
    const tip = body.tip;
    const kudosId = crypto.randomUUID();
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT OR IGNORE INTO kudos (id, feed_item_id, athlete_id, amount_sweat)
             VALUES (?, ?, ?, ?)`
        ).bind(kudosId, feedItemId, athleteId, tip),
        c.env.DB.prepare(
            `UPDATE feed_items
             SET kudos_count = (SELECT COUNT(*) FROM kudos WHERE feed_item_id = ?),
                 tipped_sweat = (SELECT COALESCE(SUM(amount_sweat), 0) FROM kudos WHERE feed_item_id = ?)
             WHERE id = ?`
        ).bind(feedItemId, feedItemId, feedItemId),
    ]);
    return c.json({ ok: true });
});

social.delete("/feed/:id/kudos", async (c) => {
    const athleteId = requireAthlete(c);
    const feedItemId = c.req.param("id");
    await c.env.DB.batch([
        c.env.DB.prepare(`DELETE FROM kudos WHERE feed_item_id = ? AND athlete_id = ?`)
            .bind(feedItemId, athleteId),
        c.env.DB.prepare(
            `UPDATE feed_items
             SET kudos_count = (SELECT COUNT(*) FROM kudos WHERE feed_item_id = ?),
                 tipped_sweat = (SELECT COALESCE(SUM(amount_sweat), 0) FROM kudos WHERE feed_item_id = ?)
             WHERE id = ?`
        ).bind(feedItemId, feedItemId, feedItemId),
    ]);
    return c.json({ ok: true });
});

social.post("/feed/:id/comments", async (c) => {
    const athleteId = requireAthlete(c);
    const feedItemId = c.req.param("id");
    const body = await parseBody(c, CommentSchema);
    const text = body.body.trim();
    const cid = crypto.randomUUID();
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT INTO comments (id, feed_item_id, athlete_id, body) VALUES (?, ?, ?, ?)`
        ).bind(cid, feedItemId, athleteId, text),
        c.env.DB.prepare(
            `UPDATE feed_items SET comment_count = comment_count + 1 WHERE id = ?`
        ).bind(feedItemId),
    ]);
    return c.json({ id: cid });
});

social.get("/feed/:id/comments", async (c) => {
    const feedItemId = c.req.param("id");
    const rows = await c.env.DB.prepare(
        `SELECT c.id, c.body, c.created_at, a.id AS aid, a.handle, a.display_name, a.avatar_tone
         FROM comments c JOIN athletes a ON a.id = c.athlete_id
         WHERE c.feed_item_id = ? ORDER BY c.created_at ASC`
    ).bind(feedItemId).all<{
        id: string; body: string; created_at: number;
        aid: string; handle: string; display_name: string; avatar_tone: string;
    }>();
    const comments = rows.results.map((r) => ({
        id: r.id,
        body: r.body,
        createdAt: r.created_at,
        athlete: { id: r.aid, handle: r.handle, displayName: r.display_name, avatarTone: r.avatar_tone },
    }));
    return c.json({ comments });
});

// ---------- Follows / mutes / reports ----------

social.post("/follow/:id", async (c) => {
    const me = requireAthlete(c);
    const target = await resolveInternalId(c.env, c.req.param("id"));
    if (!target) return c.json({ error: "not_found" }, 404);
    if (me === target) return c.json({ error: "self" }, 400);
    await c.env.DB.batch([
        c.env.DB.prepare(`INSERT OR IGNORE INTO follows (follower_id, followee_id) VALUES (?, ?)`)
            .bind(me, target),
        c.env.DB.prepare(`UPDATE athletes SET followers_count = followers_count + 1 WHERE id = ?
                          AND NOT EXISTS (SELECT 1 FROM follows WHERE follower_id = ? AND followee_id = ? AND created_at < unixepoch() - 1)`)
            .bind(target, me, target),
    ]);
    return c.json({ ok: true });
});

social.delete("/follow/:id", async (c) => {
    const me = requireAthlete(c);
    const target = await resolveInternalId(c.env, c.req.param("id"));
    if (!target) return c.json({ error: "not_found" }, 404);
    await c.env.DB.prepare(`DELETE FROM follows WHERE follower_id = ? AND followee_id = ?`)
        .bind(me, target).run();
    return c.json({ ok: true });
});

social.post("/mute/:id", async (c) => {
    const me = requireAthlete(c);
    const target = await resolveInternalId(c.env, c.req.param("id"));
    if (!target) return c.json({ error: "not_found" }, 404);
    await c.env.DB.prepare(`INSERT OR IGNORE INTO mutes (muter_id, muted_id) VALUES (?, ?)`)
        .bind(me, target).run();
    return c.json({ ok: true });
});

social.post("/report", async (c) => {
    const me = requireAthlete(c);
    const body = await parseBody(c, ReportSchema);
    const id = crypto.randomUUID();
    await c.env.DB.prepare(
        `INSERT INTO reports (id, reporter_id, feed_item_id, athlete_id, reason)
         VALUES (?, ?, ?, ?, ?)`
    ).bind(id, me, body.feedItemId ?? null, body.athleteId ?? null, body.reason).run();
    return c.json({ id });
});

// ---------- Clubs ----------

social.get("/clubs", async (c) => {
    const filter = c.req.query("filter") ?? "all";
    let sql = "SELECT * FROM clubs";
    if (filter === "joined") {
        sql = `SELECT c.* FROM clubs c JOIN club_members m ON m.club_id = c.id
               WHERE m.athlete_id = ?`;
    } else if (filter === "brands") {
        sql = `SELECT * FROM clubs WHERE is_verified_brand = 1`;
    }
    const stmt = filter === "joined"
        ? c.env.DB.prepare(sql).bind(c.get("athleteId") ?? "0xdemo_me")
        : c.env.DB.prepare(sql);
    const rows = await stmt.all<ClubRow>();
    return c.json({ clubs: rows.results.map(clubDTO) });
});

social.get("/clubs/:id", async (c) => {
    const row = await c.env.DB.prepare("SELECT * FROM clubs WHERE id = ?")
        .bind(c.req.param("id")).first<ClubRow>();
    if (!row) return c.json({ error: "not_found" }, 404);
    return c.json({ club: clubDTO(row) });
});

social.post("/clubs", async (c) => {
    const me = requireAthlete(c);
    const body = await parseBody(c, CreateClubSchema);
    const id = `clb_${crypto.randomUUID().replace(/-/g, "").slice(0, 14)}`;
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT INTO clubs (id, handle, name, tagline, description, hero_tone, tags, owner_athlete_id, member_count)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)`
        ).bind(
            id, body.handle, body.name, body.tagline ?? "",
            body.description ?? "", body.heroTone ?? "sunset",
            JSON.stringify(body.tags ?? []), me
        ),
        c.env.DB.prepare(
            `INSERT INTO club_members (club_id, athlete_id, role) VALUES (?, ?, 'owner')`
        ).bind(id, me),
    ]);
    return c.json({ id });
});

social.post("/clubs/:id/membership", async (c) => {
    const me = requireAthlete(c);
    const clubId = c.req.param("id");
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT OR IGNORE INTO club_members (club_id, athlete_id, role) VALUES (?, ?, 'member')`
        ).bind(clubId, me),
        c.env.DB.prepare(
            `UPDATE clubs SET member_count = (SELECT COUNT(*) FROM club_members WHERE club_id = ?)
             WHERE id = ?`
        ).bind(clubId, clubId),
    ]);
    return c.json({ ok: true });
});

social.delete("/clubs/:id/membership", async (c) => {
    const me = requireAthlete(c);
    const clubId = c.req.param("id");
    await c.env.DB.batch([
        c.env.DB.prepare(`DELETE FROM club_members WHERE club_id = ? AND athlete_id = ?`)
            .bind(clubId, me),
        c.env.DB.prepare(
            `UPDATE clubs SET member_count = (SELECT COUNT(*) FROM club_members WHERE club_id = ?)
             WHERE id = ?`
        ).bind(clubId, clubId),
    ]);
    return c.json({ ok: true });
});

// ---------- Challenges ----------

social.get("/challenges", async (c) => {
    const rows = await c.env.DB.prepare(
        `SELECT * FROM challenges ORDER BY ends_at ASC`
    ).all<ChallengeRow>();
    return c.json({ challenges: rows.results.map(challengeDTO) });
});

social.post("/challenges/:id/join", async (c) => {
    const me = requireAthlete(c);
    const cid = c.req.param("id");
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT OR IGNORE INTO challenge_participants (challenge_id, athlete_id, progress)
             VALUES (?, ?, 0)`
        ).bind(cid, me),
        c.env.DB.prepare(
            `UPDATE challenges
             SET participants = (SELECT COUNT(*) FROM challenge_participants WHERE challenge_id = ?)
             WHERE id = ?`
        ).bind(cid, cid),
    ]);
    return c.json({ ok: true });
});

social.delete("/challenges/:id/join", async (c) => {
    const me = requireAthlete(c);
    const cid = c.req.param("id");
    await c.env.DB.batch([
        c.env.DB.prepare(`DELETE FROM challenge_participants WHERE challenge_id = ? AND athlete_id = ?`)
            .bind(cid, me),
        c.env.DB.prepare(
            `UPDATE challenges
             SET participants = (SELECT COUNT(*) FROM challenge_participants WHERE challenge_id = ?)
             WHERE id = ?`
        ).bind(cid, cid),
    ]);
    return c.json({ ok: true });
});

// ---------- Segments ----------

social.get("/segments", async (c) => {
    const rows = await c.env.DB.prepare("SELECT * FROM segments").all<SegmentRow>();
    return c.json({ segments: rows.results.map(segmentDTO) });
});

social.get("/segments/:id/leaderboard", async (c) => {
    const sid = c.req.param("id");
    const rows = await c.env.DB.prepare(
        `SELECT e.id, e.time_seconds, e.achieved_at, a.id AS aid, a.handle,
                a.display_name, a.avatar_tone, a.tier
         FROM segment_efforts e JOIN athletes a ON a.id = e.athlete_id
         WHERE e.segment_id = ? ORDER BY e.time_seconds ASC LIMIT 50`
    ).bind(sid).all<{
        id: string; time_seconds: number; achieved_at: number;
        aid: string; handle: string; display_name: string;
        avatar_tone: string; tier: string;
    }>();
    return c.json({
        leaderboard: rows.results.map((r) => ({
            id: r.id,
            timeSeconds: r.time_seconds,
            achievedAt: r.achieved_at,
            athlete: {
                id: r.aid, handle: r.handle, displayName: r.display_name,
                avatarTone: r.avatar_tone, tier: r.tier,
            },
        })),
    });
});

social.post("/segments/:id/star", async (c) => {
    const me = requireAthlete(c);
    const sid = c.req.param("id");
    await c.env.DB.prepare(
        `INSERT OR IGNORE INTO segment_stars (segment_id, athlete_id) VALUES (?, ?)`
    ).bind(sid, me).run();
    return c.json({ ok: true });
});

social.delete("/segments/:id/star", async (c) => {
    const me = requireAthlete(c);
    const sid = c.req.param("id");
    await c.env.DB.prepare(
        `DELETE FROM segment_stars WHERE segment_id = ? AND athlete_id = ?`
    ).bind(sid, me).run();
    return c.json({ ok: true });
});

// ---------- Trophies ----------

social.get("/athletes/:id/trophies", async (c) => {
    const aid = await resolveInternalId(c.env, c.req.param("id"));
    if (!aid) return c.json({ trophies: [] });
    const rows = await c.env.DB.prepare(
        `SELECT t.*, u.progress, u.earned_at, u.showcase_index
         FROM trophies t
         LEFT JOIN trophy_unlocks u ON u.trophy_id = t.id AND u.athlete_id = ?
         ORDER BY COALESCE(u.earned_at, 9999999999) ASC`
    ).bind(aid).all<TrophyRow & {
        progress: number | null;
        earned_at: number | null;
        showcase_index: number | null;
    }>();
    const trophies = rows.results.map((r) => trophyDTO(r, {
        progress: r.progress ?? 0,
        earned_at: r.earned_at,
        showcase_index: r.showcase_index,
    }));
    return c.json({ trophies });
});

// ---------- Shoes ----------

social.get("/athletes/:id/shoes", async (c) => {
    const aid = await resolveInternalId(c.env, c.req.param("id"));
    if (!aid) return c.json({ shoes: [] });
    const rows = await c.env.DB.prepare(
        `SELECT * FROM shoes WHERE athlete_id = ? ORDER BY retired ASC, started_at DESC`
    ).bind(aid).all<ShoeRow>();
    return c.json({ shoes: rows.results.map(shoeDTO) });
});

social.post("/shoes", async (c) => {
    const me = requireAthlete(c);
    const body = await parseBody(c, AddShoeSchema);
    const id = `shoe_${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`;
    await c.env.DB.prepare(
        `INSERT INTO shoes (id, athlete_id, brand, model, nickname, tone, miles_total)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).bind(
        id, me, body.brand, body.model, body.nickname ?? null,
        body.tone, body.milesTotal
    ).run();
    return c.json({ id });
});

social.post("/shoes/:id/retire", async (c) => {
    requireAthlete(c);
    await c.env.DB.prepare(
        `UPDATE shoes SET retired = CASE retired WHEN 1 THEN 0 ELSE 1 END WHERE id = ?`
    ).bind(c.req.param("id")).run();
    return c.json({ ok: true });
});

// ---------- Personal records ----------

social.get("/athletes/:id/prs", async (c) => {
    const aid = await resolveInternalId(c.env, c.req.param("id"));
    if (!aid) return c.json({ prs: [] });
    const rows = await c.env.DB.prepare(
        `SELECT * FROM personal_records WHERE athlete_id = ? ORDER BY distance_meters ASC`
    ).bind(aid).all<PRRow>();
    return c.json({ prs: rows.results.map(prDTO) });
});

// ---------- Sweat + streak ----------

social.get("/athletes/:id/sweat", async (c) => {
    const aid = await resolveInternalId(c.env, c.req.param("id"));
    if (!aid) return c.json({ sweat: { total: 0, weekly: 0 }, streak: null });
    const [sweat, streak] = await Promise.all([
        c.env.DB.prepare("SELECT * FROM sweat_points WHERE athlete_id = ?").bind(aid)
            .first<{ total: number; weekly: number }>(),
        c.env.DB.prepare("SELECT * FROM streaks WHERE athlete_id = ?").bind(aid)
            .first<{
                current_days: number; longest_days: number;
                weekly_streak_weeks: number; staked_sweat: number; multiplier: number;
            }>(),
    ]);
    return c.json({
        sweat: sweat ?? { total: 0, weekly: 0 },
        streak: streak
            ? {
                currentDays: streak.current_days,
                longestDays: streak.longest_days,
                weeklyStreakWeeks: streak.weekly_streak_weeks,
                stakedSweat: streak.staked_sweat,
                multiplier: streak.multiplier,
              }
            : null,
    });
});

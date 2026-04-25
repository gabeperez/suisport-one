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
import { sendPushToAthlete } from "../apns.js";
import {
    parseBody, AthletePatchSchema, KudosSchema, TipSchema, CommentSchema,
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
    // Demo-identity fallback only outside production — see
    // docs/MAINNET_AUDIT.md §2. On mainnet a missing session
    // returns 401 instead of resolving to a demo athlete.
    const id = c.get("athleteId")
        ?? (c.env.ENVIRONMENT !== "production" ? "0xdemo_me" : null);
    if (!id) return c.json({ error: "unauthorized" }, 401);
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
    if (body.pronouns !== undefined) { fields.push("pronouns = ?"); binds.push(body.pronouns); }
    if (body.location !== undefined) { fields.push("location = ?"); binds.push(body.location); }
    if (body.websiteUrl !== undefined) { fields.push("website_url = ?"); binds.push(body.websiteUrl); }
    if (body.avatarTone != null) { fields.push("avatar_tone = ?"); binds.push(body.avatarTone); }
    if (body.bannerTone != null) { fields.push("banner_tone = ?"); binds.push(body.bannerTone); }
    if (body.photoR2Key !== undefined) { fields.push("photo_r2_key = ?"); binds.push(body.photoR2Key); }
    if (body.avatarR2Key !== undefined) { fields.push("avatar_r2_key = ?"); binds.push(body.avatarR2Key); }
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
    const limit = Math.min(parseInt(c.req.query("limit") ?? "30", 10), 100);

    // Composite cursor = `<orderingKey>:<feedItemId>`. The ordering
    // key is `start_date` for recent and `created_at` for kudos-sort.
    // Adding an id tiebreaker means two items sharing the same
    // ordering key (common when seeded demo rows share a second, or
    // when the same athlete logs two workouts back-to-back) page in
    // a deterministic order. Without the tiebreaker the OFFSET keeps
    // returning the same row forever.
    //
    // Wire formats supported for backwards-compat:
    //   - "<orderingKey>"              (legacy, no tiebreaker)
    //   - "<orderingKey>:<feedItemId>" (new, stable)
    const before = c.req.query("before");
    let beforeN: number | null = null;
    let beforeId: string | null = null;
    if (before) {
        const colon = before.indexOf(":");
        if (colon > 0) {
            beforeN = parseInt(before.slice(0, colon), 10);
            beforeId = before.slice(colon + 1);
            if (!Number.isFinite(beforeN)) beforeN = null;
        } else {
            beforeN = parseInt(before, 10);
            if (!Number.isFinite(beforeN)) beforeN = null;
        }
    }

    // For kudos-sort we keep kudos_count as the primary order key in
    // the SELECT (hot posts float up) but paginate by the
    // monotonic (created_at, id) pair. This keeps the cursor stable
    // even when someone kudos'd an older post between page loads.
    // The primary key still drives the visual ordering.
    const order = sort === "kudos"
        ? "fi.kudos_count DESC, fi.created_at DESC, fi.id DESC"
        : "w.start_date DESC, fi.id DESC";
    let cursorClause = "";
    const cursorBinds: unknown[] = [];
    if (beforeN != null) {
        if (beforeId != null) {
            cursorClause = sort === "kudos"
                ? "AND (fi.created_at < ? OR (fi.created_at = ? AND fi.id < ?))"
                : "AND (w.start_date < ? OR (w.start_date = ? AND fi.id < ?))";
            cursorBinds.push(beforeN, beforeN, beforeId);
        } else {
            cursorClause = sort === "kudos"
                ? "AND fi.created_at < ?"
                : "AND w.start_date < ?";
            cursorBinds.push(beforeN);
        }
    }

    const sql = `SELECT fi.*, a.id AS _a_id, w.id AS _w_id FROM feed_items fi
                 JOIN athletes a ON a.id = fi.athlete_id
                 JOIN workouts w ON w.id = fi.workout_id
                 WHERE a.suspended_at IS NULL ${cursorClause}
                 ORDER BY ${order} LIMIT ?`;
    const stmt = c.env.DB.prepare(sql).bind(...cursorBinds, limit);
    const rows = await stmt.all<FeedItemRow & { _a_id: string; _w_id: string }>();

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
    // Next cursor = "<orderingKey>:<feedItemId>" of the last row.
    // Legacy `nextBefore` as a plain number is kept for clients that
    // haven't upgraded — they just lose stability at ties.
    let nextBefore: string | null = null;
    let nextBeforeLegacy: number | null = null;
    if (rows.results.length === limit) {
        const last = rows.results[rows.results.length - 1];
        const lastW = wById.get(last.workout_id);
        const key = sort === "kudos" ? last.created_at : (lastW?.start_date ?? null);
        if (key != null) {
            nextBefore = `${key}:${last.id}`;
            nextBeforeLegacy = key;
        }
    }
    return c.json({ items, nextBefore, nextBeforeLegacy });
});

// ---------- Kudos + comments ----------

// Kudos: pure heart/clap toggle. No payment semantics. The body's
// `tip` field is accepted (older clients may send it) but ignored.
// Use POST /feed/:id/tip to send sweat.
//
// The INSERT OR IGNORE + UPDATE uses `changes()` inside SQL so the
// counter bump is skipped when the row already existed (user double-
// tapped). This avoids the old pattern of re-counting every row in
// kudos on every tap, which both drifts when rows are deleted out
// from under it AND scales O(n) per-action.
social.post("/feed/:id/kudos", async (c) => {
    const athleteId = requireAthlete(c);
    const feedItemId = c.req.param("id");
    await parseBody(c, KudosSchema).catch(() => ({ tip: 0 }));   // validate + discard
    const kudosId = crypto.randomUUID();
    const ins = await c.env.DB.prepare(
        `INSERT OR IGNORE INTO kudos (id, feed_item_id, athlete_id, amount_sweat)
         VALUES (?, ?, ?, 0)`
    ).bind(kudosId, feedItemId, athleteId).run();
    // Only bump the denormalised counter when the insert actually
    // added a row. Double-tap / replay does nothing.
    if ((ins.meta.changes ?? 0) > 0) {
        await c.env.DB.prepare(
            `UPDATE feed_items SET kudos_count = kudos_count + 1 WHERE id = ?`
        ).bind(feedItemId).run();
    }
    c.executionCtx.waitUntil(notifyKudos(c.env, feedItemId, athleteId));
    return c.json({ ok: true });
});

social.delete("/feed/:id/kudos", async (c) => {
    const athleteId = requireAthlete(c);
    const feedItemId = c.req.param("id");
    const del = await c.env.DB.prepare(
        `DELETE FROM kudos WHERE feed_item_id = ? AND athlete_id = ?`
    ).bind(feedItemId, athleteId).run();
    if ((del.meta.changes ?? 0) > 0) {
        // Clamp at 0 so a counter that drifted historically can't go
        // negative after a decrement.
        await c.env.DB.prepare(
            `UPDATE feed_items
             SET kudos_count = MAX(0, kudos_count - 1)
             WHERE id = ?`
        ).bind(feedItemId).run();
    }
    return c.json({ ok: true });
});

// Tips: append-only ledger. Each POST adds `amount` sweat (default 1)
// and is visible as an increment to feed_items.tipped_sweat. Users can
// tip the same feed item many times; unlike kudos there is no "unshift".
social.post("/feed/:id/tip", async (c) => {
    const athleteId = requireAthlete(c);
    const feedItemId = c.req.param("id");
    const { amount } = await parseBody(c, TipSchema);
    const tipId = crypto.randomUUID();
    // Incremental bump on tipped_sweat — the INSERT always succeeds
    // (tips are append-only, no uniqueness), so we always increment.
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT INTO tips (id, feed_item_id, athlete_id, amount_sweat)
             VALUES (?, ?, ?, ?)`
        ).bind(tipId, feedItemId, athleteId, amount),
        c.env.DB.prepare(
            `UPDATE feed_items
             SET tipped_sweat = tipped_sweat + ?
             WHERE id = ?`
        ).bind(amount, feedItemId),
    ]);
    c.executionCtx.waitUntil(notifyTip(c.env, feedItemId, athleteId, amount));
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
    c.executionCtx.waitUntil(notifyComment(c.env, feedItemId, athleteId, text));
    return c.json({ id: cid });
});

// Delete a comment. Allowed when the caller is either the comment
// author OR the owner of the feed item (mods get their own admin
// endpoint in admin.ts). Decrements comment_count only if the row
// actually existed.
social.delete("/feed/:id/comments/:commentId", async (c) => {
    const me = requireAthlete(c);
    const feedItemId = c.req.param("id");
    const commentId = c.req.param("commentId");

    // Authorise: either author of the comment OR owner of the feed
    // item may delete. Two-step check is cheaper than a SQL JOIN
    // under the happy path (author deletes own comment, single lookup).
    const row = await c.env.DB.prepare(
        `SELECT c.athlete_id AS author_id, fi.athlete_id AS owner_id
         FROM comments c
         JOIN feed_items fi ON fi.id = c.feed_item_id
         WHERE c.id = ? AND c.feed_item_id = ?`
    ).bind(commentId, feedItemId).first<{
        author_id: string; owner_id: string;
    }>();
    if (!row) return c.json({ error: "not_found" }, 404);
    if (row.author_id !== me && row.owner_id !== me) {
        return c.json({ error: "forbidden" }, 403);
    }

    const del = await c.env.DB.prepare(
        `DELETE FROM comments WHERE id = ? AND feed_item_id = ?`
    ).bind(commentId, feedItemId).run();
    if ((del.meta.changes ?? 0) > 0) {
        await c.env.DB.prepare(
            `UPDATE feed_items
             SET comment_count = MAX(0, comment_count - 1)
             WHERE id = ?`
        ).bind(feedItemId).run();
    }
    return c.json({ ok: true });
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

// Follow. Use D1 meta.changes on the INSERT to gate the counter
// bump — the NOT EXISTS / time-window guard that was here before was
// racy (two concurrent follows inside 1s would both see "no row",
// insert once, and bump twice). With INSERT OR IGNORE + changes()
// the DB itself guarantees at most one bump per (follower, followee)
// pair for the lifetime of that row.
social.post("/follow/:id", async (c) => {
    const me = requireAthlete(c);
    const target = await resolveInternalId(c.env, c.req.param("id"));
    if (!target) return c.json({ error: "not_found" }, 404);
    if (me === target) return c.json({ error: "self" }, 400);

    const ins = await c.env.DB.prepare(
        `INSERT OR IGNORE INTO follows (follower_id, followee_id) VALUES (?, ?)`
    ).bind(me, target).run();
    if ((ins.meta.changes ?? 0) > 0) {
        await c.env.DB.batch([
            c.env.DB.prepare(
                `UPDATE athletes SET followers_count = followers_count + 1 WHERE id = ?`
            ).bind(target),
            c.env.DB.prepare(
                `UPDATE athletes SET following_count = following_count + 1 WHERE id = ?`
            ).bind(me),
        ]);
    }
    return c.json({ ok: true });
});

social.delete("/follow/:id", async (c) => {
    const me = requireAthlete(c);
    const target = await resolveInternalId(c.env, c.req.param("id"));
    if (!target) return c.json({ error: "not_found" }, 404);
    // DELETE returns changes=0 when the row wasn't there (idempotent
    // unfollow). Only decrement when we actually removed something so
    // we don't underflow the counters.
    const del = await c.env.DB.prepare(
        `DELETE FROM follows WHERE follower_id = ? AND followee_id = ?`
    ).bind(me, target).run();
    if ((del.meta.changes ?? 0) > 0) {
        await c.env.DB.batch([
            c.env.DB.prepare(
                `UPDATE athletes SET followers_count = MAX(0, followers_count - 1) WHERE id = ?`
            ).bind(target),
            c.env.DB.prepare(
                `UPDATE athletes SET following_count = MAX(0, following_count - 1) WHERE id = ?`
            ).bind(me),
        ]);
    }
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

// Inverse of POST /mute/:id — letting the user unmute somebody. We
// always return 200 even when the row didn't exist (idempotent).
social.delete("/mute/:id", async (c) => {
    const me = requireAthlete(c);
    const target = await resolveInternalId(c.env, c.req.param("id"));
    if (!target) return c.json({ error: "not_found" }, 404);
    await c.env.DB.prepare(`DELETE FROM mutes WHERE muter_id = ? AND muted_id = ?`)
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
    // Demo-identity fallback only outside production. On mainnet,
    // requesting joined clubs without a session resolves to no
    // athlete and the JOIN returns nothing (intentional).
    const meId = c.get("athleteId")
        ?? (c.env.ENVIRONMENT !== "production" ? "0xdemo_me" : "");
    const stmt = filter === "joined"
        ? c.env.DB.prepare(sql).bind(meId)
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
    const ins = await c.env.DB.prepare(
        `INSERT OR IGNORE INTO club_members (club_id, athlete_id, role) VALUES (?, ?, 'member')`
    ).bind(clubId, me).run();
    if ((ins.meta.changes ?? 0) > 0) {
        await c.env.DB.prepare(
            `UPDATE clubs SET member_count = member_count + 1 WHERE id = ?`
        ).bind(clubId).run();
    }
    return c.json({ ok: true });
});

social.delete("/clubs/:id/membership", async (c) => {
    const me = requireAthlete(c);
    const clubId = c.req.param("id");
    const del = await c.env.DB.prepare(
        `DELETE FROM club_members WHERE club_id = ? AND athlete_id = ?`
    ).bind(clubId, me).run();
    if ((del.meta.changes ?? 0) > 0) {
        await c.env.DB.prepare(
            `UPDATE clubs SET member_count = MAX(0, member_count - 1) WHERE id = ?`
        ).bind(clubId).run();
    }
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
    const ins = await c.env.DB.prepare(
        `INSERT OR IGNORE INTO challenge_participants (challenge_id, athlete_id, progress)
         VALUES (?, ?, 0)`
    ).bind(cid, me).run();
    if ((ins.meta.changes ?? 0) > 0) {
        await c.env.DB.prepare(
            `UPDATE challenges SET participants = participants + 1 WHERE id = ?`
        ).bind(cid).run();
    }
    return c.json({ ok: true });
});

social.delete("/challenges/:id/join", async (c) => {
    const me = requireAthlete(c);
    const cid = c.req.param("id");
    const del = await c.env.DB.prepare(
        `DELETE FROM challenge_participants WHERE challenge_id = ? AND athlete_id = ?`
    ).bind(cid, me).run();
    if ((del.meta.changes ?? 0) > 0) {
        await c.env.DB.prepare(
            `UPDATE challenges SET participants = MAX(0, participants - 1) WHERE id = ?`
        ).bind(cid).run();
    }
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

// ---------- Push notification helpers ----------

/// Look up the owner of a feed item + the actor's display name, then
/// send a kudos push. No-op if the actor IS the owner (self-kudos
/// shouldn't ping the user's own phone).
async function notifyKudos(
    env: Env, feedItemId: string, actorId: string
): Promise<void> {
    try {
        const pair = await actorAndOwner(env, feedItemId, actorId);
        if (!pair) return;
        await sendPushToAthlete(env, pair.owner_id,
            { title: "SuiSport ONE", body: `${pair.who} gave you kudos` },
            {
                threadId: `feed:${feedItemId}`,
                category: "KUDOS",
                payload: { deepLink: `suisport://feed/${feedItemId}` },
            });
    } catch {}
}

async function notifyTip(
    env: Env, feedItemId: string, actorId: string, amount: number
): Promise<void> {
    try {
        const pair = await actorAndOwner(env, feedItemId, actorId);
        if (!pair) return;
        await sendPushToAthlete(env, pair.owner_id,
            { title: "SuiSport ONE", body: `${pair.who} tipped you ${amount} ⚡` },
            {
                threadId: `feed:${feedItemId}`,
                category: "TIP",
                payload: { deepLink: `suisport://feed/${feedItemId}` },
            });
    } catch {}
}

async function actorAndOwner(
    env: Env, feedItemId: string, actorId: string
): Promise<{ owner_id: string; who: string } | null> {
    const row = await env.DB.prepare(
        `SELECT fi.athlete_id AS owner_id, a.display_name AS actor_name, a.handle AS actor_handle
         FROM feed_items fi, athletes a
         WHERE fi.id = ? AND a.id = ?`
    ).bind(feedItemId, actorId).first<{
        owner_id: string; actor_name: string | null; actor_handle: string | null;
    }>();
    if (!row || row.owner_id === actorId) return null;
    const who = row.actor_name || (row.actor_handle ? `@${row.actor_handle}` : "Someone");
    return { owner_id: row.owner_id, who };
}

async function notifyComment(
    env: Env, feedItemId: string, actorId: string, text: string
): Promise<void> {
    try {
        const pair = await env.DB.prepare(
            `SELECT fi.athlete_id AS owner_id, a.display_name AS actor_name, a.handle AS actor_handle
             FROM feed_items fi, athletes a
             WHERE fi.id = ? AND a.id = ?`
        ).bind(feedItemId, actorId).first<{
            owner_id: string; actor_name: string | null; actor_handle: string | null;
        }>();
        if (!pair || pair.owner_id === actorId) return;
        const who = pair.actor_name || (pair.actor_handle ? `@${pair.actor_handle}` : "Someone");
        const snippet = text.length > 120 ? text.slice(0, 117) + "…" : text;
        await sendPushToAthlete(env, pair.owner_id,
            { title: who, body: snippet },
            {
                threadId: `feed:${feedItemId}`,
                category: "COMMENT",
                payload: { deepLink: `suisport://feed/${feedItemId}` },
            });
    } catch {}
}

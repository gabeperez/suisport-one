import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { adminGuard } from "../auth.js";

export const admin = new Hono<{ Bindings: Env; Variables: Variables }>();

admin.use("*", adminGuard);

// Drops every row with is_demo=1 across the schema. The order matters —
// child tables first, then parents, so foreign-key constraints pass.
const DEMO_TABLES_IN_ORDER = [
    "comments",
    "kudos",
    "feed_items",
    "segment_stars",
    "segment_efforts",
    "challenge_participants",
    "club_members",
    "trophy_unlocks",
    "shoe_usage",
    "shoes",
    "personal_records",
    "streaks",
    "sweat_points",
    "follows",
    "workouts",
    "segments",
    "challenges",
    "trophies",
    "clubs",
    "athletes",
    "users",
] as const;

admin.post("/admin/clear-demo", async (c) => {
    const counts: Record<string, number> = {};
    for (const t of DEMO_TABLES_IN_ORDER) {
        // Not all tables have is_demo (e.g. segment_stars doesn't),
        // so gate on the column existing.
        const hasColumn = await c.env.DB.prepare(
            `SELECT 1 FROM pragma_table_info(?) WHERE name = 'is_demo'`
        ).bind(t).first();
        if (!hasColumn) { counts[t] = 0; continue; }
        const res = await c.env.DB.prepare(
            `DELETE FROM ${t} WHERE is_demo = 1`
        ).run();
        counts[t] = res.meta.changes ?? 0;
    }
    await c.env.DB.prepare(
        `UPDATE schema_meta SET value = '0', updated_at = unixepoch() WHERE key = 'demo_seeded'`
    ).run();
    return c.json({ ok: true, deleted: counts });
});

admin.post("/admin/reseed", async (c) => {
    // Signals the CI/wrangler seed runner — we don't re-exec seed.sql from
    // inside the Worker (no file access). Caller runs:
    //     npx wrangler d1 execute suisport-db --remote --file=./seed.sql
    return c.json({
        ok: true,
        note: "Run `npm run db:seed` from the cloudflare/ directory to reload demo data.",
    });
});

admin.get("/admin/status", async (c) => {
    const tables = [
        "athletes", "feed_items", "workouts", "clubs", "challenges",
        "segments", "trophies", "shoes", "kudos", "comments", "follows",
    ];
    const stats: Record<string, { total: number; demo: number }> = {};
    for (const t of tables) {
        const total = await c.env.DB.prepare(`SELECT COUNT(*) AS n FROM ${t}`)
            .first<{ n: number }>();
        const demo = await c.env.DB.prepare(`SELECT COUNT(*) AS n FROM ${t} WHERE is_demo = 1`)
            .first<{ n: number }>();
        stats[t] = { total: total?.n ?? 0, demo: demo?.n ?? 0 };
    }
    return c.json({ tables: stats, environment: c.env.ENVIRONMENT });
});

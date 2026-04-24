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
    const unresolved = await c.env.DB.prepare(
        `SELECT COUNT(*) AS n FROM reports WHERE resolved_at IS NULL`
    ).first<{ n: number }>();
    const suspended = await c.env.DB.prepare(
        `SELECT COUNT(*) AS n FROM athletes WHERE suspended_at IS NOT NULL`
    ).first<{ n: number }>();
    return c.json({
        tables: stats,
        openReports: unresolved?.n ?? 0,
        suspendedAthletes: suspended?.n ?? 0,
        environment: c.env.ENVIRONMENT,
    });
});

// ---------- Moderation queue ----------

admin.get("/admin/reports", async (c) => {
    const status = c.req.query("status") ?? "open";
    const whereClause = status === "resolved"
        ? "r.resolved_at IS NOT NULL"
        : "r.resolved_at IS NULL";
    const rows = await c.env.DB.prepare(
        `SELECT r.id, r.reason, r.created_at, r.resolved_at, r.resolution_note,
                r.feed_item_id, r.athlete_id AS target_athlete_id,
                reporter.handle AS reporter_handle,
                reporter.display_name AS reporter_name,
                target.handle AS target_handle,
                target.display_name AS target_name,
                fi.title AS feed_title, fi.caption AS feed_caption
         FROM reports r
         LEFT JOIN athletes reporter ON reporter.id = r.reporter_id
         LEFT JOIN athletes target   ON target.id   = r.athlete_id
         LEFT JOIN feed_items fi     ON fi.id       = r.feed_item_id
         WHERE ${whereClause}
         ORDER BY r.created_at DESC
         LIMIT 200`
    ).all<Record<string, unknown>>();
    return c.json({ reports: rows.results ?? [] });
});

admin.post("/admin/reports/:id/resolve", async (c) => {
    const id = c.req.param("id");
    const body: { note?: string; actor?: string } =
        await c.req.json<{ note?: string; actor?: string }>().catch(() => ({}));
    await c.env.DB.prepare(
        `UPDATE reports
         SET resolved_at = unixepoch(),
             resolved_by = ?,
             resolution_note = ?
         WHERE id = ?`
    ).bind(body.actor ?? "admin", body.note ?? null, id).run();
    return c.json({ ok: true });
});

// ---------- Soft-ban ----------

admin.post("/admin/athletes/:id/suspend", async (c) => {
    const body: { reason?: string } =
        await c.req.json<{ reason?: string }>().catch(() => ({}));
    const res = await c.env.DB.prepare(
        `UPDATE athletes
         SET suspended_at = unixepoch(),
             suspended_reason = ?
         WHERE (user_id = ? OR id = ?) AND suspended_at IS NULL`
    ).bind(body.reason ?? "policy", c.req.param("id"), c.req.param("id")).run();
    return c.json({ ok: true, suspended: (res.meta.changes ?? 0) > 0 });
});

admin.post("/admin/athletes/:id/unsuspend", async (c) => {
    const res = await c.env.DB.prepare(
        `UPDATE athletes
         SET suspended_at = NULL, suspended_reason = NULL
         WHERE (user_id = ? OR id = ?) AND suspended_at IS NOT NULL`
    ).bind(c.req.param("id"), c.req.param("id")).run();
    return c.json({ ok: true, unsuspended: (res.meta.changes ?? 0) > 0 });
});

admin.get("/admin/suspended", async (c) => {
    const rows = await c.env.DB.prepare(
        `SELECT id, user_id, handle, display_name, suspended_at, suspended_reason
         FROM athletes
         WHERE suspended_at IS NOT NULL
         ORDER BY suspended_at DESC
         LIMIT 200`
    ).all<Record<string, unknown>>();
    return c.json({ athletes: rows.results ?? [] });
});

// ---------- On-chain pipeline ----------

admin.get("/admin/onchain-pending", async (c) => {
    // Surfaces workouts whose submit_workout failed at POST time
    // AND haven't been reconciled by the cron yet. Either they're
    // early in the backoff window or they hit MAX_RETRIES and have
    // parked. Ordering: most retried first (most painful, likely
    // needs manual intervention).
    const rows = await c.env.DB.prepare(
        `SELECT w.id, w.athlete_id, a.handle AS athlete_handle,
                w.type, w.start_date, w.points, w.walrus_blob_id,
                w.onchain_retry_count, w.onchain_last_retry_at,
                w.onchain_last_error
         FROM workouts w
         LEFT JOIN athletes a ON a.id = w.athlete_id
         WHERE w.sui_tx_digest LIKE 'pending_%'
         ORDER BY w.onchain_retry_count DESC, w.start_date ASC
         LIMIT 100`
    ).all<Record<string, unknown>>();
    return c.json({ workouts: rows.results ?? [] });
});

// ---------- Rewards catalog management ----------

admin.post("/admin/rewards/catalog", async (c) => {
    const body = await c.req.json<{
        sku: string; title: string; subtitle?: string; description?: string;
        imageUrl?: string; costPoints: number; codes: string[]; active?: boolean;
    }>();
    const id = `rw_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;
    const codePool = (body.codes ?? []).join("\n");
    await c.env.DB.prepare(
        `INSERT INTO rewards_catalog
           (id, sku, title, subtitle, description, image_url, cost_points,
            code_pool, stock_total, stock_claimed, active)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)`
    ).bind(
        id, body.sku, body.title, body.subtitle ?? null, body.description ?? null,
        body.imageUrl ?? null, body.costPoints,
        codePool, body.codes?.length ?? 0, body.active === false ? 0 : 1,
    ).run();
    return c.json({ ok: true, id });
});

admin.get("/admin/rewards/catalog", async (c) => {
    const rows = await c.env.DB.prepare(
        `SELECT id, sku, title, cost_points, stock_total, stock_claimed, active
         FROM rewards_catalog
         ORDER BY created_at DESC`
    ).all<Record<string, unknown>>();
    return c.json({ items: rows.results ?? [] });
});

admin.get("/admin/attest-keys", async (c) => {
    // App Attest keys by verification status. Pre-hardening keys
    // have cert_chain_ok=0 and can no longer sign assertions (see
    // verifyAssertion refusal path). Admin sees who needs to
    // re-attest so we can nudge those users in-app.
    const rows = await c.env.DB.prepare(
        `SELECT k.key_id, k.athlete_id, a.handle AS athlete_handle,
                k.cert_chain_ok, k.counter, k.last_used_at
         FROM app_attest_keys k
         LEFT JOIN athletes a ON a.id = k.athlete_id
         ORDER BY k.cert_chain_ok ASC, k.last_used_at DESC
         LIMIT 200`
    ).all<Record<string, unknown>>();
    return c.json({ keys: rows.results ?? [] });
});

// ---------- Admin HTML dashboard ----------
//
// A minimal protected HTML page for reviewing reports + suspending
// athletes in a browser. Auth: client sends X-Admin-Token via fetch()
// headers after the page prompts for it on first load.

admin.get("/admin/dashboard", async (c) => {
    return c.html(dashboardHtml);
});

const dashboardHtml = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>SuiSport — Admin</title>
<style>
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; }
    body {
        margin: 0; padding: 24px;
        font: 14px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        background: #fafafa; color: #111;
    }
    @media (prefers-color-scheme: dark) {
        body { background: #0a0a0a; color: #f0f0f0; }
        .card { background: #141414 !important; border-color: #222 !important; }
        input, button { background: #1a1a1a !important; color: #f0f0f0 !important; border-color: #333 !important; }
    }
    h1 { font-size: 22px; letter-spacing: -0.01em; margin: 0 0 18px; }
    .stats { display: flex; gap: 14px; margin-bottom: 18px; flex-wrap: wrap; }
    .stat {
        background: white; border: 1px solid #e5e5e5;
        padding: 12px 16px; border-radius: 10px; min-width: 130px;
    }
    .stat .n { font-size: 22px; font-weight: 700; }
    .stat .l { color: #6a6a6a; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
    .card {
        background: white; border: 1px solid #e5e5e5;
        border-radius: 12px; padding: 14px; margin-bottom: 12px;
    }
    .row { display: flex; justify-content: space-between; gap: 12px; align-items: start; }
    .meta { color: #6a6a6a; font-size: 12px; margin-top: 2px; }
    .reason {
        display: inline-block; padding: 2px 8px; border-radius: 8px;
        background: #fde8e8; color: #b00; font-size: 11px; font-weight: 600;
    }
    @media (prefers-color-scheme: dark) {
        .reason { background: #3b1e1e; color: #f88; }
    }
    button {
        font: inherit; padding: 6px 12px; border-radius: 8px;
        border: 1px solid #ddd; background: #f4f4f4; cursor: pointer;
    }
    button.primary { background: #2172DC; color: white; border-color: #2172DC; }
    button.danger  { background: #c03; color: white; border-color: #c03; }
    input {
        padding: 10px 12px; border: 1px solid #ddd; border-radius: 8px;
        width: 100%; font: inherit;
    }
    .empty { color: #6a6a6a; padding: 40px 0; text-align: center; }
    .quote {
        border-left: 3px solid #e5e5e5; padding: 4px 12px;
        color: #444; margin-top: 8px; font-style: italic;
    }
    @media (prefers-color-scheme: dark) {
        .quote { color: #bbb; border-color: #333; }
    }
</style>
</head>
<body>
    <h1>SuiSport Moderation</h1>
    <div id="auth-block">
        <p>Paste your <code>X-Admin-Token</code> to load the dashboard.</p>
        <input id="tok" type="password" placeholder="Admin token" />
        <button class="primary" style="margin-top:8px" onclick="window.signIn()">Load</button>
    </div>
    <div id="dash" style="display:none">
        <div class="stats" id="stats"></div>
        <h2 style="font-size:16px;margin:18px 0 8px">Open reports</h2>
        <div id="reports"></div>
        <h2 style="font-size:16px;margin:18px 0 8px">Suspended athletes</h2>
        <div id="suspended"></div>
        <h2 style="font-size:16px;margin:18px 0 8px">On-chain pipeline — stuck workouts</h2>
        <div id="onchain-pending"></div>
        <h2 style="font-size:16px;margin:18px 0 8px">App Attest keys</h2>
        <div id="attest-keys"></div>
    </div>
<script>
    let token = "";
    const api = (p) => fetch(p, { headers: { "X-Admin-Token": token } });
    const post = (p, body) => fetch(p, {
        method: "POST",
        headers: { "X-Admin-Token": token, "Content-Type": "application/json" },
        body: JSON.stringify(body || {}),
    });

    window.signIn = async () => {
        token = document.getElementById("tok").value;
        const status = await api("/v1/admin/status");
        if (!status.ok) { alert("Bad token"); return; }
        document.getElementById("auth-block").style.display = "none";
        document.getElementById("dash").style.display = "block";
        renderAll();
    };

    async function renderAll() {
        const s = await (await api("/v1/admin/status")).json();
        document.getElementById("stats").innerHTML = \`
            <div class="stat"><div class="n">\${s.openReports}</div><div class="l">Open reports</div></div>
            <div class="stat"><div class="n">\${s.suspendedAthletes}</div><div class="l">Suspended</div></div>
            <div class="stat"><div class="n">\${s.tables.athletes.total}</div><div class="l">Athletes</div></div>
            <div class="stat"><div class="n">\${s.tables.feed_items.total}</div><div class="l">Feed items</div></div>\`;

        const { reports } = await (await api("/v1/admin/reports?status=open")).json();
        const reportsEl = document.getElementById("reports");
        if (!reports.length) reportsEl.innerHTML = '<div class="empty">No open reports. 🎉</div>';
        else reportsEl.innerHTML = reports.map(r => \`
            <div class="card">
              <div class="row">
                <div style="flex:1">
                  <div><span class="reason">\${r.reason}</span>
                    <strong>\${r.reporter_name || r.reporter_handle || "?"}</strong>
                    reported
                    <strong>\${r.target_name || r.target_handle || "(feed item)"}</strong>
                  </div>
                  <div class="meta">\${new Date(r.created_at*1000).toLocaleString()}</div>
                  \${r.feed_title ? \`<div class="quote">\${r.feed_title}\${r.feed_caption ? " — "+r.feed_caption : ""}</div>\` : ""}
                </div>
                <div style="display:flex;gap:6px;flex-direction:column">
                  <button onclick="resolveReport('\${r.id}')">Resolve</button>
                  \${r.target_athlete_id ? \`<button class="danger" onclick="suspend('\${r.target_athlete_id}', 'reported: '+'\${r.reason}')">Suspend</button>\` : ""}
                </div>
              </div>
            </div>\`).join("");

        const { athletes: suspendedList } = await (await api("/v1/admin/suspended")).json();
        const suspEl = document.getElementById("suspended");
        if (!suspendedList.length) suspEl.innerHTML = '<div class="empty">None — clean shop.</div>';
        else suspEl.innerHTML = suspendedList.map(a => \`
            <div class="card">
              <div class="row">
                <div style="flex:1">
                  <div><strong>\${a.display_name || a.handle || a.id}</strong>
                    <span class="meta">@\${a.handle || "—"}</span></div>
                  <div class="meta">suspended \${new Date(a.suspended_at*1000).toLocaleString()}
                    \${a.suspended_reason ? " — " + a.suspended_reason : ""}</div>
                </div>
                <div><button onclick="unsuspend('\${a.id}')">Unsuspend</button></div>
              </div>
            </div>\`).join("");

        const { workouts: pendingList } = await (await api("/v1/admin/onchain-pending")).json();
        const pendEl = document.getElementById("onchain-pending");
        if (!pendingList.length) pendEl.innerHTML = '<div class="empty">All workouts settled on-chain. 🎉</div>';
        else pendEl.innerHTML = pendingList.map(w => \`
            <div class="card">
              <div class="row">
                <div style="flex:1">
                  <div><strong>\${w.type}</strong> —
                    \${w.points} pts — @\${w.athlete_handle || w.athlete_id}</div>
                  <div class="meta">
                    retry #\${w.onchain_retry_count}
                    \${w.onchain_last_retry_at ? " — last @ " + new Date(w.onchain_last_retry_at*1000).toLocaleString() : ""}
                    \${w.walrus_blob_id ? "" : " — ⚠ no walrus blob"}
                  </div>
                  \${w.onchain_last_error ? \`<div class="quote">\${w.onchain_last_error}</div>\` : ""}
                </div>
              </div>
            </div>\`).join("");

        const { keys: attestKeys } = await (await api("/v1/admin/attest-keys")).json();
        const attEl = document.getElementById("attest-keys");
        if (!attestKeys.length) attEl.innerHTML = '<div class="empty">No App Attest keys registered yet.</div>';
        else attEl.innerHTML = attestKeys.map(k => \`
            <div class="card">
              <div class="row">
                <div style="flex:1">
                  <div>@\${k.athlete_handle || k.athlete_id}
                    <span class="reason" style="background:\${k.cert_chain_ok ? '#e8f7ea' : '#fde8e8'};color:\${k.cert_chain_ok ? '#060' : '#b00'}">
                      \${k.cert_chain_ok ? "verified" : "unverified"}
                    </span></div>
                  <div class="meta">counter \${k.counter}
                    \${k.last_used_at ? " — last used " + new Date(k.last_used_at*1000).toLocaleString() : ""}</div>
                </div>
              </div>
            </div>\`).join("");
    }

    window.resolveReport = async (id) => {
        const note = prompt("Resolution note (optional)?") || "";
        await post("/v1/admin/reports/" + id + "/resolve", { note });
        renderAll();
    };
    window.suspend = async (athleteId, reason) => {
        if (!confirm("Suspend " + athleteId + "?")) return;
        await post("/v1/admin/athletes/" + athleteId + "/suspend", { reason });
        renderAll();
    };
    window.unsuspend = async (athleteId) => {
        if (!confirm("Unsuspend " + athleteId + "?")) return;
        await post("/v1/admin/athletes/" + athleteId + "/unsuspend", {});
        renderAll();
    };
</script>
</body>
</html>`;

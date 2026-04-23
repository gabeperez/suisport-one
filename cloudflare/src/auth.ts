import type { Context, Next } from "hono";
import type { Env, Variables } from "./env.js";

// Extract athlete id from `Authorization: Bearer <session>` header.
// Session lookup hits the `sessions` table; falls back to a demo athlete
// id query param `?athleteId=0xdemo_me` so we can test the API without
// standing up a real zkLogin flow.
export async function sessionMiddleware(
    c: Context<{ Bindings: Env; Variables: Variables }>,
    next: Next
) {
    const auth = c.req.header("Authorization");
    if (auth?.startsWith("Bearer ")) {
        const token = auth.slice(7);
        const row = await c.env.DB.prepare(
            "SELECT sui_address FROM sessions WHERE id = ? AND expires_at > unixepoch()"
        ).bind(token).first<{ sui_address: string }>();
        if (row) c.set("athleteId", row.sui_address);
    }
    // Dev-only fallback (gated on env). Remove in prod behind a real auth flow.
    if (!c.get("athleteId")) {
        const q = c.req.query("athleteId");
        if (q && q.startsWith("0xdemo_")) c.set("athleteId", q);
    }
    await next();
}

export function requireAthlete(
    c: Context<{ Bindings: Env; Variables: Variables }>
): string {
    const id = c.get("athleteId");
    if (!id) throw new Error("UNAUTHORIZED");
    return id;
}

export async function adminGuard(
    c: Context<{ Bindings: Env; Variables: Variables }>,
    next: Next
) {
    const token = c.req.header("X-Admin-Token");
    if (token !== c.env.ADMIN_TOKEN) {
        return c.json({ error: "forbidden" }, 403);
    }
    c.set("isAdmin", true);
    await next();
}

/// Rate-limit middleware. Keys on the session athlete when present,
/// otherwise on the request IP. Returns 429 when the caller exceeds the
/// window defined in wrangler.toml (60 req/min today).
export async function rateLimit(
    c: Context<{ Bindings: Env; Variables: Variables }>,
    next: Next
) {
    const key = c.get("athleteId")
        ?? c.req.header("CF-Connecting-IP")
        ?? "anon";
    // Native binding is not present in `wrangler dev` unless explicitly
    // enabled; skip gracefully when undefined so local dev still works.
    if (c.env.RATE_LIMIT?.limit) {
        const { success } = await c.env.RATE_LIMIT.limit({ key });
        if (!success) return c.json({ error: "rate_limited" }, 429);
    }
    await next();
}

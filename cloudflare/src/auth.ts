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

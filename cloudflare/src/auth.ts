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
    // Dev-only fallback for curl smoke tests. Hard-disabled when
    // ENVIRONMENT === "production" so a misconfigured mainnet deploy
    // cannot authenticate as anyone via a query param. Resolves the
    // BLOCKER flagged in docs/MAINNET_AUDIT.md §2.
    if (c.env.ENVIRONMENT !== "production" && !c.get("athleteId")) {
        const q = c.req.query("athleteId");
        if (q && (q.startsWith("0xdemo_") || /^0x[a-fA-F0-9]{64}$/.test(q))) {
            c.set("athleteId", q);
        }
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

/// Constant-time string compare. Plain `===` on a secret leaks length
/// + per-byte timing under remote-timing attacks; this version always
/// walks the longer of the two strings and OR-folds the differences.
function timingSafeEqual(a: string, b: string): boolean {
    const len = Math.max(a.length, b.length);
    let diff = a.length ^ b.length;
    for (let i = 0; i < len; i++) {
        const ca = i < a.length ? a.charCodeAt(i) : 0;
        const cb = i < b.length ? b.charCodeAt(i) : 0;
        diff |= ca ^ cb;
    }
    return diff === 0;
}

export async function adminGuard(
    c: Context<{ Bindings: Env; Variables: Variables }>,
    next: Next
) {
    const token = c.req.header("X-Admin-Token") ?? "";
    const expected = c.env.ADMIN_TOKEN ?? "";
    // Constant-time compare — see helper above. Audit §9.
    if (!expected || !timingSafeEqual(token, expected)) {
        return c.json({ error: "forbidden" }, 403);
    }
    c.set("isAdmin", true);
    await next();
}

/// Optional App Attest gate for mutating routes.
///
/// Clients pass three headers when they have a registered attestation
/// key:
///   X-AppAttest-Key-Id        base64url key id the client holds
///   X-AppAttest-Assertion     base64 CBOR assertion from
///                             DCAppAttestService.generateAssertion
///   X-AppAttest-ClientData    base64 clientDataHash the assertion covers
///
/// Behavior:
///   - Missing headers + ATTEST_STRICT=true  →  401 "attest_required"
///   - Missing headers + strict off           →  pass-through (beta)
///   - Present but invalid                    →  401 "attest_invalid"
///   - Present + valid                        →  pass-through; counter
///                                               bumped by verifyAssertion
export async function attestMiddleware(
    c: Context<{ Bindings: Env; Variables: Variables }>,
    next: Next
) {
    const keyId = c.req.header("X-AppAttest-Key-Id");
    const assertion = c.req.header("X-AppAttest-Assertion");
    const clientData = c.req.header("X-AppAttest-ClientData");
    const strict = c.env.ATTEST_STRICT === "true";

    if (!keyId || !assertion || !clientData) {
        if (strict) return c.json({ error: "attest_required" }, 401);
        return next();
    }

    // Import lazily to avoid paying the CBOR parse cost for the strict=false
    // pass-through path on every request.
    try {
        const { verifyAssertion } = await import("./appattest.js");
        const padded = clientData.replace(/-/g, "+").replace(/_/g, "/");
        const clientDataBytes = Uint8Array.from(
            atob(padded + "=".repeat((4 - (padded.length % 4)) % 4)),
            (ch) => ch.charCodeAt(0)
        );
        const res = await verifyAssertion(
            c.env, keyId, assertion, clientDataBytes.buffer as ArrayBuffer
        );
        if (!res.ok) {
            return c.json({ error: "attest_invalid", reason: res.reason }, 401);
        }
    } catch (err) {
        return c.json({
            error: "attest_invalid",
            reason: err instanceof Error ? err.message : "unknown",
        }, 401);
    }
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

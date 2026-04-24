import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { parseBody, AuthExchangeSchema } from "../validation.js";
import { hasEnokiKey, resolveZkLogin, decodeJwtClaims } from "../enoki.js";
import { resolveSuiNS } from "../sui.js";

/// Strip the ".sui" suffix + sanitize for use as a handle.
/// "alice.sui" → "alice"; "my-name.sui" → "my_name"
function suinsToHandle(suins: string): string {
    const stem = suins.replace(/\.sui$/, "");
    return stem.toLowerCase().replace(/[^a-z0-9_]/g, "_").slice(0, 24) || "athlete";
}

function suinsToDisplayName(suins: string): string {
    const stem = suins.replace(/\.sui$/, "");
    // Title-case each segment separated by - or _
    return stem.split(/[-_]/).map(w =>
        w.length ? w[0].toUpperCase() + w.slice(1) : w
    ).join(" ");
}

export const auth = new Hono<{ Bindings: Env; Variables: Variables }>();

// Exchange an OAuth id token for a session.
//
// When `ENOKI_SECRET_KEY` is configured, we run the real Enoki zkLogin
// flow — Enoki verifies the JWT signature against the issuer's JWKS and
// returns the user's Sui address. Without the key we fall back to a
// deterministic SHA-256 derivation so dev + friends-beta keep working
// with a stable identity even before the Enoki project is set up.
//
// The returned sessionJwt is an opaque random id that indexes into the
// `sessions` table; the iOS client stores it and sends it as a bearer
// token on subsequent requests.
auth.post("/auth/session", async (c) => {
    const body = await parseBody(c, AuthExchangeSchema);

    let suiAddress: string;
    let verifiedEnoki = false;
    let claims: Record<string, unknown> = {};

    if (hasEnokiKey(c.env)) {
        try {
            const res = await resolveZkLogin(c.env, body.idToken);
            suiAddress = res.address;
            verifiedEnoki = true;
            // Pull display name / email from the id token for the
            // initial profile row; Enoki has already verified it.
            claims = decodeJwtClaims(body.idToken);
        } catch (err) {
            return c.json({
                error: "auth_failed",
                detail: err instanceof Error ? err.message : "unknown",
            }, 401);
        }
    } else {
        suiAddress = await deterministicAddr(body.idToken || body.provider);
    }

    // SuiNS reverse lookup — when the user already owns `alice.sui` we
    // pre-fill their profile with it. Silent on-error; names are optional.
    const suinsName = await resolveSuiNS(c.env, suiAddress);

    const claimedName = typeof claims.name === "string" ? claims.name : undefined;
    const claimedEmail = typeof claims.email === "string" ? claims.email : undefined;
    const displayName = body.displayName
        ?? (suinsName ? suinsToDisplayName(suinsName) : undefined)
        ?? claimedName
        ?? claimedEmail
        ?? "Athlete";
    const handle = suinsName
        ? suinsToHandle(suinsName)
        : (displayName.toLowerCase().replace(/[^a-z0-9]/g, "_").slice(0, 24)
            || `u${suiAddress.slice(2, 10)}`);

    const sessionId = crypto.randomUUID();
    const expiresAt = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30;

    // Upsert user + athlete row. IDs match suiAddress so athletes and
    // users are 1:1.
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT OR IGNORE INTO users (sui_address, display_name, provider)
             VALUES (?, ?, ?)`
        ).bind(suiAddress, displayName, body.provider),
        c.env.DB.prepare(
            `INSERT INTO athletes (id, handle, display_name, avatar_tone, suins_name)
             VALUES (?, ?, ?, 'sunset', ?)
             ON CONFLICT(id) DO UPDATE SET
                suins_name = COALESCE(excluded.suins_name, athletes.suins_name)`
        ).bind(suiAddress, handle, displayName, suinsName),
        c.env.DB.prepare(
            `INSERT INTO sessions (id, sui_address, expires_at) VALUES (?, ?, ?)`
        ).bind(sessionId, suiAddress, expiresAt),
    ]);

    // Read back the newly-created (or existing) user_id so the client
    // gets a stable public identity from the very first call. This is
    // cheap — we just did an upsert so the row is hot.
    const userRow = await c.env.DB.prepare(
        `SELECT user_id FROM athletes WHERE id = ?`
    ).bind(suiAddress).first<{ user_id: string }>();

    return c.json({
        sessionJwt: sessionId,
        userId: userRow?.user_id ?? null,
        suiAddress,
        displayName,
        handle,
        suinsName,
        verified: verifiedEnoki,
    });
});

auth.post("/auth/signout", async (c) => {
    const authHeader = c.req.header("Authorization");
    if (authHeader?.startsWith("Bearer ")) {
        await c.env.DB.prepare(`DELETE FROM sessions WHERE id = ?`)
            .bind(authHeader.slice(7)).run();
    }
    return c.json({ ok: true });
});

// Diagnostic: returns what the server thinks the current session is.
// Lets the iOS app's debug panel distinguish "Enoki ran + returned a
// real zkLogin address" from "Enoki was skipped/failed + we're on the
// deterministic mock" without requiring end-to-end instrumentation.
auth.get("/auth/whoami", async (c) => {
    const id = c.get("athleteId");
    if (!id) {
        return c.json({
            authenticated: false,
            enokiConfigured: hasEnokiKey(c.env),
        });
    }
    const row = await c.env.DB.prepare(
        `SELECT a.id, a.user_id, a.handle, a.display_name, a.suins_name,
                u.provider, u.created_at
         FROM athletes a
         LEFT JOIN users u ON u.sui_address = a.id
         WHERE a.id = ? LIMIT 1`
    ).bind(id).first<{
        id: string; user_id: string; handle: string;
        display_name: string; suins_name: string | null;
        provider: string | null; created_at: number | null;
    }>();
    if (!row) return c.json({ authenticated: false }, 404);

    // An address shape of 66 hex chars (0x + 64 nibbles) means it's a
    // full-width Sui address — either a real zkLogin result or a
    // matching-shape mock. 42 chars = truncated mock from before we
    // fixed the pre-Enoki fallback.
    const looksLikeFullSuiAddress = /^0x[a-fA-F0-9]{64}$/.test(row.id);

    return c.json({
        authenticated: true,
        enokiConfigured: hasEnokiKey(c.env),
        userId: row.user_id,
        suiAddress: row.id,
        addressShape: looksLikeFullSuiAddress ? "sui_valid" : "mock_truncated",
        handle: row.handle,
        displayName: row.display_name,
        suinsName: row.suins_name,
        suinsPresentOnThisNetwork: row.suins_name != null,
        provider: row.provider,
        firstSeenAt: row.created_at,
    });
});

async function deterministicAddr(seed: string): Promise<string> {
    const data = new TextEncoder().encode(seed);
    const hash = await crypto.subtle.digest("SHA-256", data);
    const hex = [...new Uint8Array(hash)]
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    return `0x${hex.slice(0, 40)}`;
}

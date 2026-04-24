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

    return c.json({
        sessionJwt: sessionId,
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

async function deterministicAddr(seed: string): Promise<string> {
    const data = new TextEncoder().encode(seed);
    const hash = await crypto.subtle.digest("SHA-256", data);
    const hex = [...new Uint8Array(hash)]
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    return `0x${hex.slice(0, 40)}`;
}

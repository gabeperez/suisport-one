import { Hono } from "hono";
import type { Env, Variables } from "../env.js";
import { parseBody, AuthExchangeSchema } from "../validation.js";

export const auth = new Hono<{ Bindings: Env; Variables: Variables }>();

// Exchange an OAuth id token for a session. This is a STUB until Enoki
// zkLogin is wired up — right now we derive a deterministic fake Sui
// address from the id token so the client gets a stable identity to work
// with. Matches the iOS AuthService behavior.
auth.post("/auth/session", async (c) => {
    const body = await parseBody(c, AuthExchangeSchema);

    const suiAddress = await deterministicAddr(body.idToken || body.provider);
    const sessionId = crypto.randomUUID();
    const expiresAt = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30;

    // Upsert user + athlete row.
    await c.env.DB.batch([
        c.env.DB.prepare(
            `INSERT OR IGNORE INTO users (sui_address, display_name, provider)
             VALUES (?, ?, ?)`
        ).bind(suiAddress, body.displayName ?? "Athlete", body.provider),
        c.env.DB.prepare(
            `INSERT OR IGNORE INTO athletes (id, handle, display_name, avatar_tone)
             VALUES (?, ?, ?, 'sunset')`
        ).bind(
            suiAddress,
            (body.displayName ?? suiAddress).toLowerCase().replace(/[^a-z0-9]/g, "_").slice(0, 24),
            body.displayName ?? "Athlete"
        ),
        c.env.DB.prepare(
            `INSERT INTO sessions (id, sui_address, expires_at) VALUES (?, ?, ?)`
        ).bind(sessionId, suiAddress, expiresAt),
    ]);

    return c.json({
        sessionJwt: sessionId,
        suiAddress,
        displayName: body.displayName ?? "Athlete",
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

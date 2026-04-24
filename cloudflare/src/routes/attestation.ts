import { Hono } from "hono";
import { z } from "zod";
import type { Env, Variables } from "../env.js";
import { requireAthlete } from "../auth.js";
import { parseBody } from "../validation.js";
import { registerAttestation, AttestError } from "../appattest.js";

export const attestation = new Hono<{ Bindings: Env; Variables: Variables }>();

// Issue a one-time nonce for App Attest registration. TTL = 5 min,
// single-use. The iOS client passes the base64url value as the
// clientDataHash (SHA-256'd) into DCAppAttestService.attestKey.
attestation.get("/attestation/challenge", async (c) => {
    const me = requireAthlete(c);
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    const b64url = btoa(String.fromCharCode(...bytes))
        .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    await c.env.DB.prepare(
        `INSERT INTO attest_challenges (challenge, athlete_id) VALUES (?, ?)`
    ).bind(b64url, me).run();
    return c.json({ challenge: b64url, ttlSeconds: 300 });
});

const RegisterSchema = z.object({
    keyId: z.string().min(1).max(256),
    attestation: z.string().min(1).max(16_384),
    challenge: z.string().min(1).max(256),
});

attestation.post("/attestation/register", async (c) => {
    const me = requireAthlete(c);
    const body = await parseBody(c, RegisterSchema);
    try {
        const res = await registerAttestation(
            c.env, me, body.keyId, body.attestation, body.challenge
        );
        return c.json(res);
    } catch (err) {
        if (err instanceof AttestError) {
            return c.json({ error: "attest_failed", code: err.code }, 400);
        }
        throw err;
    }
});

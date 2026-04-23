import type { FastifyInstance } from "fastify";
import crypto from "node:crypto";

// In-memory challenge store — replace with Redis in production.
const challenges = new Map<string, number>();
const TTL_MS = 120_000;

export async function healthRoutes(app: FastifyInstance) {
  /**
   * GET /health/challenge
   * Issues a one-time challenge bytes the client must include in its App Attest
   * assertion. Also used as a freshness primitive (120 s TTL).
   */
  app.get("/challenge", async (_req, reply) => {
    const c = crypto.randomBytes(32).toString("base64url");
    challenges.set(c, Date.now() + TTL_MS);
    return reply.send({ challenge: c, ttlMs: TTL_MS });
  });

  app.get("/ping", async (_req, reply) => reply.send({ ok: true }));
}

export function consumeChallenge(c: string): boolean {
  const exp = challenges.get(c);
  if (!exp || exp < Date.now()) return false;
  challenges.delete(c);
  return true;
}

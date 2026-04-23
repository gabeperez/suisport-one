import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { exchangeWithEnoki } from "../services/enoki.js";

const ExchangeBody = z.object({
  provider: z.enum(["apple", "google"]),
  idToken: z.string(),
  // ephemeral public key (base64) the client wants embedded in the zk proof nonce
  ephemeralPublicKey: z.string(),
  maxEpoch: z.number().int(),
  randomness: z.string(),
});

export async function authRoutes(app: FastifyInstance) {
  /**
   * POST /auth/session
   * Exchanges an OAuth id_token for a zkLogin proof + derived Sui address.
   * Client never sees its own private material — only a session JWT back.
   */
  app.post("/session", async (req, reply) => {
    const body = ExchangeBody.parse(req.body);
    const result = await exchangeWithEnoki(body);
    return reply.send({
      sessionJwt: result.sessionJwt,
      suiAddress: result.suiAddress,
      displayName: result.displayName,
      avatarUrl: result.avatarUrl,
      expiresAt: result.expiresAt,
    });
  });
}

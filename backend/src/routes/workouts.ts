import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { verifyAppAttest } from "../services/appAttest.js";
import { uploadToWalrus } from "../services/walrus.js";
import { signAttestation } from "../services/oracle.js";
import { submitWorkoutPTB } from "../services/sui.js";

const SubmitBody = z.object({
  canonical: z.object({
    v: z.literal(1),
    uuid: z.string().uuid(),
    type: z.number().int(),
    startUTC: z.number().int(),
    endUTC: z.number().int(),
    duration_s: z.number().int(),
    distance_m: z.number().int().nullable(),
    energy_kcal: z.number().int().nullable(),
    avg_hr: z.number().int().nullable(),
    route_hash: z.string().nullable(),
    source: z.string(),
    device: z.string().nullable(),
    user_entered: z.boolean(),
  }),
  attestation: z.object({
    keyId: z.string(),
    assertion: z.string(), // base64
    challenge: z.string(), // base64, previously issued by /health/challenge
  }),
  encryptedBlob: z.string().nullable().optional(),      // base64 — Seal-encrypted payload for Walrus
  sessionJwt: z.string(),
});

export async function workoutRoutes(app: FastifyInstance) {
  /**
   * POST /workouts
   * 1. Verify App Attest assertion against the canonical-payload + challenge hash.
   * 2. Upload (pre-encrypted) blob to Walrus Quilt; returned blob id is owned by the user.
   * 3. Run plausibility checks (pace, HR distribution, motion cross-check).
   * 4. Sign an ed25519 attestation digest with the oracle key.
   * 5. Build a sponsored PTB via Enoki that calls `rewards_engine::submit_workout`.
   * 6. Return { txDigest, pointsMinted, walrusBlobId } to the client.
   */
  app.post("/", async (req, reply) => {
    const body = SubmitBody.parse(req.body);

    await verifyAppAttest(body.attestation);
    const walrusBlobId = body.encryptedBlob
      ? await uploadToWalrus(body.encryptedBlob, { ownerAddress: "TODO-from-session" })
      : "";
    const signed = await signAttestation(body.canonical, walrusBlobId);
    const tx = await submitWorkoutPTB({ canonical: body.canonical, signed, walrusBlobId });

    return reply.send({
      txDigest: tx.digest,
      pointsMinted: signed.rewardAmount,
      walrusBlobId,
    });
  });
}

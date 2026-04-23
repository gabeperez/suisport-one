import crypto from "node:crypto";
import blake from "blake2b";
import { config } from "../config.js";

type Canonical = {
  v: 1;
  uuid: string;
  type: number;
  startUTC: number;
  endUTC: number;
  duration_s: number;
  distance_m: number | null;
  energy_kcal: number | null;
  avg_hr: number | null;
  route_hash: string | null;
  source: string;
  device: string | null;
  user_entered: boolean;
};

export type SignedAttestation = {
  nonce: string;              // base64
  expiresAtMs: number;
  msgDigestHex: string;
  signatureHex: string;
  rewardAmount: number;       // SWEAT mist
};

export async function signAttestation(c: Canonical, walrusBlobId: string): Promise<SignedAttestation> {
  const nonce = crypto.randomBytes(16);
  const expiresAtMs = Date.now() + 5 * 60 * 1000;

  const rewardAmount = computeReward(c);

  // Canonical digest: BLAKE2b256 over a concatenated byte layout matching the Move code.
  const h = blake(32);
  h.update(Buffer.from(c.uuid));
  h.update(nonce);
  h.update(u64ToLE(expiresAtMs));
  h.update(Buffer.from([c.type]));
  h.update(u64ToLE(c.startUTC));
  h.update(u32ToLE(c.duration_s));
  h.update(u32ToLE(c.distance_m ?? 0));
  h.update(u32ToLE(c.energy_kcal ?? 0));
  h.update(Buffer.from(walrusBlobId, "utf8"));
  h.update(u64ToLE(rewardAmount));
  const digest = Buffer.from(h.digest());

  // Ed25519 signing — in production this is done inside an HSM.
  if (!config.oracle.privateKeyHex) throw new Error("oracle key missing");
  const privBytes = Buffer.from(config.oracle.privateKeyHex, "hex");
  const keyPair = crypto.createPrivateKey({
    key: Buffer.concat([
      Buffer.from("302e020100300506032b657004220420", "hex"),
      privBytes.subarray(0, 32),
    ]),
    format: "der",
    type: "pkcs8",
  });
  const signature = crypto.sign(null, digest, keyPair);

  return {
    nonce: nonce.toString("base64"),
    expiresAtMs,
    msgDigestHex: digest.toString("hex"),
    signatureHex: signature.toString("hex"),
    rewardAmount,
  };
}

/** Conservative reward formula. Mirror of the iOS `SweatPoints.forWorkout`. */
function computeReward(c: Canonical): number {
  const minutes = c.duration_s / 60;
  const km = (c.distance_m ?? 0) / 1000;
  let base = 0;
  if ([37, 52, 13, 24].includes(c.type)) base = km * 60 + minutes * 2; // run/walk/bike/hike
  else if (c.type === 46) base = km * 300 + minutes * 4;               // swim
  else base = minutes * 6;
  if (c.user_entered) base *= 0.3;
  return Math.max(0, Math.round(base));
}

function u32ToLE(n: number): Buffer {
  const b = Buffer.alloc(4);
  b.writeUInt32LE(Math.max(0, Math.min(0xffffffff, Math.floor(n))));
  return b;
}
function u64ToLE(n: number): Buffer {
  const b = Buffer.alloc(8);
  b.writeBigUInt64LE(BigInt(Math.floor(n)));
  return b;
}

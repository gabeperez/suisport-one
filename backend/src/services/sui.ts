import type { SignedAttestation } from "./oracle.js";

type SubmitInput = {
  canonical: {
    uuid: string;
    type: number;
    startUTC: number;
    duration_s: number;
    distance_m: number | null;
    energy_kcal: number | null;
  };
  signed: SignedAttestation;
  walrusBlobId: string;
};

/**
 * Build and dispatch a sponsored `rewards_engine::submit_workout` call.
 *
 * Real implementation uses @mysten/sui `TransactionBlock` + Enoki sponsored-tx:
 *   - `tx.moveCall({ target: `${pkg}::rewards_engine::submit_workout`, arguments: [...] })`
 *   - POST to Enoki /v1/transaction-blocks/sponsor to get `{ sponsorSignature, bytes }`
 *   - User signs the bytes via their zkLogin proof (done earlier, served back to client)
 *   - Submit with `client.executeTransactionBlock({ transactionBlock, signature: [user, sponsor] })`
 */
export async function submitWorkoutPTB(_input: SubmitInput): Promise<{ digest: string }> {
  throw new Error("sui:submitWorkoutPTB not implemented");
}

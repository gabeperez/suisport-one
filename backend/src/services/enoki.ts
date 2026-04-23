import { config } from "../config.js";

type ExchangeInput = {
  provider: "apple" | "google";
  idToken: string;
  ephemeralPublicKey: string;
  maxEpoch: number;
  randomness: string;
};

type ExchangeResult = {
  sessionJwt: string;
  suiAddress: string;
  displayName: string;
  avatarUrl: string | null;
  expiresAt: number;
};

/**
 * Exchange an OAuth id_token for a zkLogin proof + Sui address.
 *
 * Real implementation:
 *   - POST https://api.enoki.mystenlabs.com/v1/zklogin/zkp with { network, jwt,
 *     ephemeralPublicKey, maxEpoch, randomness } and the Enoki API key header.
 *   - Derive the user's address from the proof: `getZkLoginSignature` + `toSuiAddress`.
 *   - Mint a short-lived session JWT (sub = suiAddress) and return.
 */
export async function exchangeWithEnoki(input: ExchangeInput): Promise<ExchangeResult> {
  if (!config.enoki.apiKey) {
    throw new Error("Enoki API key not configured");
  }
  // Implementation placeholder — wire once ENOKI_API_KEY is set and a test JWT is captured.
  throw new Error("enoki:exchange not implemented");
}

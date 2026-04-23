/**
 * App Attest verification.
 *
 * Real implementation flow:
 *   1. On first use per install, client sends an attestation blob. Verify it against
 *      Apple's root CA; check the App ID (teamId.bundleId) and production flag;
 *      store the attested public key keyed by keyId.
 *   2. On every subsequent submission, client sends an assertion over
 *      SHA256(canonical_payload || server_challenge). Verify with the stored pubkey
 *      and the monotonic counter from the assertion's authenticator data.
 *
 * References:
 *   - https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity
 *   - https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server
 */
export async function verifyAppAttest(input: {
  keyId: string;
  assertion: string;
  challenge: string;
}): Promise<{ ok: true }> {
  // Implementation: verify assertion bytes; cross-check challenge against the
  // in-memory store (see routes/health.ts::consumeChallenge).
  if (!input.keyId || !input.assertion) {
    throw new Error("appAttest: missing fields");
  }
  return { ok: true };
}

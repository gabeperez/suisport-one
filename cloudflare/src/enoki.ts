import { EnokiClient, EnokiClientError } from "@mysten/enoki";

// Thin wrapper around the Enoki SDK. Two entry points:
//   - `hasKey(env)` tells the caller whether live Enoki is configured.
//   - `resolveZkLogin(env, idToken)` returns the Sui address for an
//     OAuth id token. Throws on Enoki errors so the caller can decide
//     whether to surface the failure or fall back to the legacy mock.

export function hasEnokiKey(env: { ENOKI_SECRET_KEY?: string }): boolean {
    return !!env.ENOKI_SECRET_KEY && env.ENOKI_SECRET_KEY.startsWith("enoki_");
}

export async function resolveZkLogin(
    env: { ENOKI_SECRET_KEY?: string },
    idToken: string
): Promise<{ address: string; publicKey: string; salt: string }> {
    if (!hasEnokiKey(env)) {
        throw new Error("ENOKI_NOT_CONFIGURED");
    }
    const enoki = new EnokiClient({ apiKey: env.ENOKI_SECRET_KEY! });
    try {
        const { address, publicKey, salt } = await enoki.getZkLogin({ jwt: idToken });
        return { address, publicKey, salt };
    } catch (err) {
        if (err instanceof EnokiClientError) {
            throw new Error(`ENOKI_${err.code || "ERROR"}: ${err.message}`);
        }
        throw err;
    }
}

// Minimal JWT claim extractor so we can pick out the display name /
// email from the id token after Enoki has already verified the
// signature. Does NOT verify — Enoki does that.
export function decodeJwtClaims(jwt: string): Record<string, unknown> {
    const parts = jwt.split(".");
    if (parts.length !== 3) throw new Error("INVALID_JWT");
    const payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = payload + "=".repeat((4 - (payload.length % 4)) % 4);
    const json = atob(padded);
    return JSON.parse(json);
}

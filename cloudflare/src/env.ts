export type Env = {
    DB: D1Database;
    MEDIA: R2Bucket;
    RATE_LIMIT: RateLimit;
    ADMIN_TOKEN: string;
    ENVIRONMENT: string;
    // Optional — when present, /v1/auth/session performs real zkLogin
    // via Enoki; otherwise it falls back to a deterministic mock.
    ENOKI_SECRET_KEY?: string;
    // Optional — when present, /v1/attestation/register enforces real
    // App Attest verification; otherwise it accepts but flags.
    APPATTEST_APP_ID?: string;
};

// Cloudflare's native rate-limiting API binding.
// https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/
export interface RateLimit {
    limit(opts: { key: string }): Promise<{ success: boolean }>;
}

export type Variables = {
    // Session-scoped variables populated by auth middleware.
    athleteId?: string;
    isAdmin?: boolean;
};

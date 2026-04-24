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
    // ---- Sui / Walrus (all optional; pipeline falls back to stubs) ----
    SUI_NETWORK?: string;                // "testnet" | "mainnet" | RPC URL
    SUI_PACKAGE_ID?: string;             // 0x... after `sui client publish`
    SUI_REWARDS_ENGINE_ID?: string;      // shared RewardsEngine
    SUI_ORACLE_CAP_ID?: string;          // OracleCap owned by operator
    SUI_VERSION_OBJECT_ID?: string;      // shared Version
    SUI_OPERATOR_KEY?: string;           // base64 Ed25519 secret key
    ORACLE_PRIVATE_KEY?: string;         // base64 Ed25519 secret key (attestation signer)
    WALRUS_PUBLISHER_URL?: string;
    WALRUS_AGGREGATOR_URL?: string;
    // Indexer cursor — advanced per-tick; not user-set.
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

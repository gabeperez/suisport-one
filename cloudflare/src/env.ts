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
    // Format: "<TEAM_ID>.<BUNDLE_ID>", e.g. "ABCDE12345.gimme.coffee.iHealth"
    APPATTEST_APP_ID?: string;
    // "production" | "development". Selects the expected aaguid in
    // authData: production = "appattest" + 7 null bytes; development
    // = "appattestdevelop". Defaults to production when unset.
    APPATTEST_ENV?: "production" | "development";
    // "true" → mutating routes require a valid App Attest assertion.
    // Anything else (default) → accept requests without assertion
    // headers so existing clients continue working through the beta.
    ATTEST_STRICT?: string;
    // ---- Sui / Walrus (all optional; pipeline falls back to stubs) ----
    SUI_NETWORK?: string;                // "testnet" | "mainnet" | RPC URL
    SUI_PACKAGE_ID?: string;             // 0x... after `sui client publish`
    SUI_REWARDS_ENGINE_ID?: string;      // shared RewardsEngine
    SUI_ORACLE_CAP_ID?: string;          // OracleCap owned by operator
    SUI_VERSION_OBJECT_ID?: string;      // shared Version
    SUI_OPERATOR_KEY?: string;           // base64 Ed25519 secret key (single-key legacy)
    // Optional comma-separated list of operator keys. When set we
    // fan out users across these keys, so multiple UserProfile objects
    // can be submitted in parallel without racing on gas coins or
    // version objects owned by one keypair. If SUI_OPERATOR_KEYS is
    // empty we fall back to SUI_OPERATOR_KEY (single-key mode).
    SUI_OPERATOR_KEYS?: string;
    ORACLE_PRIVATE_KEY?: string;         // base64 Ed25519 secret key (attestation signer)
    WALRUS_PUBLISHER_URL?: string;
    WALRUS_AGGREGATOR_URL?: string;
    // ---- Apple Push Notification service (all optional) ----
    APNS_KEY_ID?: string;
    APNS_TEAM_ID?: string;
    APNS_BUNDLE_ID?: string;
    APNS_KEY?: string;                            // AuthKey_<kid>.p8 contents
    APNS_ENV?: "production" | "sandbox";
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

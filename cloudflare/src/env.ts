export type Env = {
    DB: D1Database;
    MEDIA: R2Bucket;
    RATE_LIMIT: RateLimit;
    ADMIN_TOKEN: string;
    ENVIRONMENT: string;
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

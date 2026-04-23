export type Env = {
    DB: D1Database;
    MEDIA: R2Bucket;
    ADMIN_TOKEN: string;
    ENVIRONMENT: string;
};

export type Variables = {
    // Session-scoped variables populated by auth middleware.
    athleteId?: string;
    isAdmin?: boolean;
};

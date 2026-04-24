-- Device tokens for Apple Push Notification service.
--
-- One row per (athlete, device-token) pair. Tokens rotate when the
-- user reinstalls or restores from backup, so we key on (token)
-- and update `athlete_id` + `updated_at` on each register call
-- (INSERT OR REPLACE semantics). A single athlete may have multiple
-- rows (iPhone + iPad).
CREATE TABLE IF NOT EXISTS push_tokens (
    token           TEXT PRIMARY KEY,
    athlete_id      TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    platform        TEXT NOT NULL DEFAULT 'ios',
    env             TEXT NOT NULL DEFAULT 'production',  -- "production" | "development"
    created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    last_error      TEXT,
    last_error_at   INTEGER,
    disabled_at     INTEGER                 -- set when APNs returns 410 Gone
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_athlete
ON push_tokens(athlete_id)
WHERE disabled_at IS NULL;

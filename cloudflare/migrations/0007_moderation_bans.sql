-- Moderation queue: resolution columns on reports.
-- Each report starts unresolved; an admin acts on it by setting
-- resolved_at (+ an optional note + who resolved it).
ALTER TABLE reports ADD COLUMN resolved_at INTEGER;
ALTER TABLE reports ADD COLUMN resolved_by TEXT;
ALTER TABLE reports ADD COLUMN resolution_note TEXT;

CREATE INDEX IF NOT EXISTS idx_reports_unresolved
    ON reports(created_at DESC)
    WHERE resolved_at IS NULL;

-- Soft-ban columns on athletes. `suspended_at IS NOT NULL` = banned.
-- Feed + athlete-list reads filter these out; the athlete's own
-- /me lookup still returns their row so they can see their account is
-- suspended and (eventually) appeal.
ALTER TABLE athletes ADD COLUMN suspended_at INTEGER;
ALTER TABLE athletes ADD COLUMN suspended_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_athletes_suspended
    ON athletes(suspended_at)
    WHERE suspended_at IS NOT NULL;

-- Age gate storage. Nullable until captured during onboarding.
ALTER TABLE athletes ADD COLUMN dob INTEGER;           -- unix seconds
ALTER TABLE athletes ADD COLUMN age_verified_at INTEGER;

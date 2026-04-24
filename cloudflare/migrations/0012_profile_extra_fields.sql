-- Extra profile fields surfaced through PATCH /me.
--
-- `bio` already exists (added in 0001 with TEXT NOT NULL? check: in 0001
-- it's declared nullable). We widen the iOS-facing profile with a
-- separate avatar key (distinct from the generic photo_r2_key, which
-- covers legacy uploads) plus a handful of vanity fields so the profile
-- card can carry pronouns / a website link / a location.
--
-- ALTER TABLE ADD COLUMN is idempotent only in the sense that it's
-- run-once-per-deploy; since D1 migrations track applied state we
-- don't need IF NOT EXISTS guards. If you're running this against a
-- dev DB where columns already exist, `.dev` that DB and re-seed.

ALTER TABLE athletes ADD COLUMN pronouns TEXT;
ALTER TABLE athletes ADD COLUMN website_url TEXT;
ALTER TABLE athletes ADD COLUMN avatar_r2_key TEXT;

-- When we support a pool of operator keypairs (SUI_OPERATOR_KEYS),
-- each UserProfile is owned by exactly one operator. Remember which
-- one here so re-submits always sign with the correct keypair even
-- if the hash-bucket mapping shifts (e.g. after a key rotation /
-- pool expansion). Backfill is not necessary because the legacy
-- single-key path still works unconditionally — on a pool expansion
-- the pre-existing rows without operator_address just fall through
-- to the hash-based path, which in a single-key-at-mint-time env
-- will still pick the same (only) key.
ALTER TABLE sui_user_profiles ADD COLUMN operator_address TEXT;

-- Trophy seed rows used by the unlock writer in workouts.ts. Every id
-- is deterministic so the writer can `INSERT OR IGNORE INTO
-- trophy_unlocks` keyed on them without needing a lookup pass.
--
-- We seed these as is_demo=0 so real users see them unlocked — the
-- existing demo trophies (tro_demo_*) stay untouched and keep their
-- is_demo=1 flag.
INSERT OR IGNORE INTO trophies (id, title, subtitle, icon, category, rarity, gradient_tones, is_demo) VALUES
('tro_first_run',       'First Run',         'Completed your first workout.',          'figure.walk.motion',  'milestone', 'common',    '["sunset"]',           0),
('tro_distance_5k',     '5K Club',           'Covered 5 km in a single workout.',      'figure.run',          'milestone', 'common',    '["sunset","ember"]',   0),
('tro_distance_10k',    '10K Club',          'Covered 10 km in a single workout.',     'figure.run',          'milestone', 'rare',      '["ember","grape"]',    0),
('tro_distance_half',   'Half Marathon',     'Covered a half marathon in one go.',     'medal.star.fill',     'milestone', 'rare',      '["forest","ocean"]',   0),
('tro_distance_full',   'Marathon',          'Covered a full marathon in one go.',     'medal.fill',          'milestone', 'epic',      '["grape","ember"]',    0),
('tro_streak_7',        'Week Streak',       '7 days in a row.',                       'flame.fill',          'streak',    'common',    '["sunset","ember"]',   0),
('tro_streak_30',       'Month Streak',      '30 days in a row.',                      'flame.circle.fill',   'streak',    'epic',      '["ember"]',            0),
('tro_streak_100',      '100 Day Streak',    '100 days in a row. Unhinged.',           'crown.fill',          'streak',    'legendary', '["ember","grape"]',    0),
('tro_points_1k',       '1,000 Points',      'Hit 1,000 lifetime sweat points.',       'star.fill',           'milestone', 'common',    '["sunset"]',           0),
('tro_points_10k',      '10,000 Points',     'Hit 10,000 lifetime sweat points.',      'star.circle.fill',    'milestone', 'rare',      '["sunset","grape"]',   0),
('tro_points_100k',     '100,000 Points',    'Hit 100,000 lifetime sweat points.',     'sparkles',            'milestone', 'legendary', '["sunset","ember","grape"]', 0);

-- Last-resort log when the redeem path loses a code because BOTH the
-- spend AND the refund-push-back fail. The operator can read this and
-- credit the user manually.
CREATE TABLE IF NOT EXISTS redemption_refunds (
    id             TEXT PRIMARY KEY,
    athlete_id     TEXT,
    catalog_id     TEXT,
    code           TEXT NOT NULL,
    reason         TEXT NOT NULL,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_redemption_refunds_created
ON redemption_refunds(created_at DESC);

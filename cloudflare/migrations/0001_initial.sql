-- SuiSport D1 schema
-- Every mutable table carries `is_demo INTEGER DEFAULT 0`.
-- Seeded/fixture rows are written with 1; anything a real user creates is 0.
-- `DELETE FROM <t> WHERE is_demo = 1` resets the demo surface without
-- touching real data.

PRAGMA foreign_keys = ON;

-- ---------- Users / auth ----------

CREATE TABLE IF NOT EXISTS users (
    sui_address    TEXT PRIMARY KEY,
    display_name   TEXT NOT NULL,
    provider       TEXT NOT NULL,           -- google | apple | email
    goal           TEXT,                    -- loseWeight | runFaster | buildMuscle | stayConsistent | justEarn
    created_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_users_demo ON users(is_demo);

CREATE TABLE IF NOT EXISTS sessions (
    id             TEXT PRIMARY KEY,
    sui_address    TEXT NOT NULL REFERENCES users(sui_address) ON DELETE CASCADE,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    expires_at     INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_address ON sessions(sui_address);

-- ---------- Athletes (social profile card; 1:1 with user) ----------

CREATE TABLE IF NOT EXISTS athletes (
    id                      TEXT PRIMARY KEY,          -- matches sui_address for real; "0xdemo_ajoy" etc for demo
    handle                  TEXT NOT NULL UNIQUE,
    display_name            TEXT NOT NULL,
    avatar_tone             TEXT NOT NULL DEFAULT 'sunset',
    banner_tone             TEXT NOT NULL DEFAULT 'sunset',
    verified                INTEGER NOT NULL DEFAULT 0,
    tier                    TEXT NOT NULL DEFAULT 'starter',
    total_workouts          INTEGER NOT NULL DEFAULT 0,
    followers_count         INTEGER NOT NULL DEFAULT 0,
    following_count         INTEGER NOT NULL DEFAULT 0,
    bio                     TEXT,
    location                TEXT,
    photo_r2_key            TEXT,                      -- key in R2 bucket (null = use gradient avatar)
    is_demo                 INTEGER NOT NULL DEFAULT 0,
    created_at              INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at              INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_athletes_handle ON athletes(handle);
CREATE INDEX IF NOT EXISTS idx_athletes_demo ON athletes(is_demo);

-- ---------- Follows / mutes ----------

CREATE TABLE IF NOT EXISTS follows (
    follower_id    TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    followee_id    TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (follower_id, followee_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_followee ON follows(followee_id);
CREATE INDEX IF NOT EXISTS idx_follows_demo ON follows(is_demo);

CREATE TABLE IF NOT EXISTS mutes (
    muter_id       TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    muted_id       TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    PRIMARY KEY (muter_id, muted_id)
);

-- ---------- Workouts + feed items ----------

CREATE TABLE IF NOT EXISTS workouts (
    id                      TEXT PRIMARY KEY,
    athlete_id              TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    type                    TEXT NOT NULL,             -- run | walk | ride | hike | swim | other
    start_date              INTEGER NOT NULL,          -- unix seconds
    duration_seconds        INTEGER NOT NULL,
    distance_meters         REAL,
    energy_kcal             REAL,
    avg_heart_rate          REAL,
    pace_seconds_per_km     REAL,
    points                  INTEGER NOT NULL DEFAULT 0,
    verified                INTEGER NOT NULL DEFAULT 0,
    walrus_blob_id          TEXT,                      -- canonical blob on Walrus (null until uploaded)
    sui_object_id           TEXT,                      -- on-chain workout NFT (null until minted)
    sui_tx_digest           TEXT,
    is_demo                 INTEGER NOT NULL DEFAULT 0,
    created_at              INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_workouts_athlete ON workouts(athlete_id);
CREATE INDEX IF NOT EXISTS idx_workouts_start ON workouts(start_date DESC);
CREATE INDEX IF NOT EXISTS idx_workouts_demo ON workouts(is_demo);

CREATE TABLE IF NOT EXISTS feed_items (
    id                      TEXT PRIMARY KEY,
    athlete_id              TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    workout_id              TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    title                   TEXT NOT NULL,
    caption                 TEXT,
    map_preview_seed        INTEGER NOT NULL DEFAULT 0,
    kudos_count             INTEGER NOT NULL DEFAULT 0,
    comment_count           INTEGER NOT NULL DEFAULT 0,
    tipped_sweat            INTEGER NOT NULL DEFAULT 0,
    is_demo                 INTEGER NOT NULL DEFAULT 0,
    created_at              INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_feed_athlete ON feed_items(athlete_id);
CREATE INDEX IF NOT EXISTS idx_feed_created ON feed_items(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feed_demo ON feed_items(is_demo);

CREATE TABLE IF NOT EXISTS kudos (
    id             TEXT PRIMARY KEY,
    feed_item_id   TEXT NOT NULL REFERENCES feed_items(id) ON DELETE CASCADE,
    athlete_id     TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    amount_sweat   INTEGER NOT NULL DEFAULT 0,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0,
    UNIQUE (feed_item_id, athlete_id)
);

CREATE INDEX IF NOT EXISTS idx_kudos_item ON kudos(feed_item_id);
CREATE INDEX IF NOT EXISTS idx_kudos_demo ON kudos(is_demo);

CREATE TABLE IF NOT EXISTS comments (
    id             TEXT PRIMARY KEY,
    feed_item_id   TEXT NOT NULL REFERENCES feed_items(id) ON DELETE CASCADE,
    athlete_id     TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    body           TEXT NOT NULL,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_comments_item ON comments(feed_item_id);
CREATE INDEX IF NOT EXISTS idx_comments_demo ON comments(is_demo);

-- ---------- Reports (moderation) ----------

CREATE TABLE IF NOT EXISTS reports (
    id             TEXT PRIMARY KEY,
    reporter_id    TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    feed_item_id   TEXT REFERENCES feed_items(id) ON DELETE CASCADE,
    athlete_id     TEXT REFERENCES athletes(id) ON DELETE CASCADE,
    reason         TEXT NOT NULL,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports(reporter_id);

-- ---------- Clubs ----------

CREATE TABLE IF NOT EXISTS clubs (
    id                      TEXT PRIMARY KEY,
    handle                  TEXT NOT NULL UNIQUE,
    name                    TEXT NOT NULL,
    tagline                 TEXT,
    description             TEXT,
    hero_tone               TEXT NOT NULL DEFAULT 'sunset',
    member_count            INTEGER NOT NULL DEFAULT 1,
    sweat_treasury          INTEGER NOT NULL DEFAULT 0,
    weekly_km               REAL NOT NULL DEFAULT 0,
    is_verified_brand       INTEGER NOT NULL DEFAULT 0,
    tags                    TEXT NOT NULL DEFAULT '[]',     -- JSON array
    banner_r2_key           TEXT,
    owner_athlete_id        TEXT REFERENCES athletes(id) ON DELETE SET NULL,
    is_demo                 INTEGER NOT NULL DEFAULT 0,
    created_at              INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_clubs_demo ON clubs(is_demo);

CREATE TABLE IF NOT EXISTS club_members (
    club_id        TEXT NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    athlete_id     TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    role           TEXT NOT NULL DEFAULT 'member',    -- member | admin | owner
    joined_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (club_id, athlete_id)
);

CREATE INDEX IF NOT EXISTS idx_club_members_athlete ON club_members(athlete_id);
CREATE INDEX IF NOT EXISTS idx_club_members_demo ON club_members(is_demo);

-- ---------- Challenges ----------

CREATE TABLE IF NOT EXISTS challenges (
    id                      TEXT PRIMARY KEY,
    title                   TEXT NOT NULL,
    subtitle                TEXT,
    sponsor                 TEXT,
    icon                    TEXT,
    tone                    TEXT NOT NULL DEFAULT 'sunset',
    goal_type               TEXT NOT NULL,             -- distance | workouts | time
    goal_value              REAL NOT NULL,
    stake_sweat             INTEGER NOT NULL DEFAULT 0,
    prize_pool_sweat        INTEGER NOT NULL DEFAULT 0,
    participants            INTEGER NOT NULL DEFAULT 0,
    starts_at               INTEGER NOT NULL,
    ends_at                 INTEGER NOT NULL,
    is_demo                 INTEGER NOT NULL DEFAULT 0,
    created_at              INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_challenges_demo ON challenges(is_demo);
CREATE INDEX IF NOT EXISTS idx_challenges_ends ON challenges(ends_at);

CREATE TABLE IF NOT EXISTS challenge_participants (
    challenge_id   TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    athlete_id     TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    progress       REAL NOT NULL DEFAULT 0,
    joined_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (challenge_id, athlete_id)
);

CREATE INDEX IF NOT EXISTS idx_challenge_participants_athlete ON challenge_participants(athlete_id);

-- ---------- Segments ----------

CREATE TABLE IF NOT EXISTS segments (
    id                      TEXT PRIMARY KEY,
    name                    TEXT NOT NULL,
    location                TEXT,
    distance_meters         REAL NOT NULL,
    elevation_gain_meters   REAL NOT NULL DEFAULT 0,
    surface                 TEXT NOT NULL DEFAULT 'road',
    kom_athlete_id          TEXT REFERENCES athletes(id) ON DELETE SET NULL,
    kom_time_seconds        INTEGER,
    is_demo                 INTEGER NOT NULL DEFAULT 0,
    created_at              INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_segments_demo ON segments(is_demo);

CREATE TABLE IF NOT EXISTS segment_efforts (
    id             TEXT PRIMARY KEY,
    segment_id     TEXT NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
    athlete_id     TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    workout_id     TEXT REFERENCES workouts(id) ON DELETE SET NULL,
    time_seconds   INTEGER NOT NULL,
    achieved_at    INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_efforts_segment ON segment_efforts(segment_id, time_seconds);
CREATE INDEX IF NOT EXISTS idx_efforts_athlete ON segment_efforts(athlete_id);

CREATE TABLE IF NOT EXISTS segment_stars (
    segment_id     TEXT NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
    athlete_id     TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    PRIMARY KEY (segment_id, athlete_id)
);

-- ---------- Trophies ----------

CREATE TABLE IF NOT EXISTS trophies (
    id                      TEXT PRIMARY KEY,
    title                   TEXT NOT NULL,
    subtitle                TEXT,
    icon                    TEXT NOT NULL,
    category                TEXT NOT NULL,             -- milestone | streak | challenge | segment | badge
    rarity                  TEXT NOT NULL DEFAULT 'common',  -- common | rare | epic | legendary
    gradient_tones          TEXT NOT NULL DEFAULT '[]',      -- JSON array of tone names
    is_demo                 INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_trophies_demo ON trophies(is_demo);

CREATE TABLE IF NOT EXISTS trophy_unlocks (
    athlete_id     TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    trophy_id      TEXT NOT NULL REFERENCES trophies(id) ON DELETE CASCADE,
    progress       REAL NOT NULL DEFAULT 0,
    earned_at      INTEGER,
    showcase_index INTEGER,                            -- 0..2 if pinned on profile
    is_demo        INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (athlete_id, trophy_id)
);

CREATE INDEX IF NOT EXISTS idx_unlocks_athlete ON trophy_unlocks(athlete_id);
CREATE INDEX IF NOT EXISTS idx_unlocks_demo ON trophy_unlocks(is_demo);

-- ---------- Gear ----------

CREATE TABLE IF NOT EXISTS shoes (
    id                      TEXT PRIMARY KEY,
    athlete_id              TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    brand                   TEXT NOT NULL,
    model                   TEXT NOT NULL,
    nickname                TEXT,
    tone                    TEXT NOT NULL DEFAULT 'sunset',
    miles_used              REAL NOT NULL DEFAULT 0,
    miles_total             REAL NOT NULL DEFAULT 800,
    retired                 INTEGER NOT NULL DEFAULT 0,
    started_at              INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo                 INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_shoes_athlete ON shoes(athlete_id);
CREATE INDEX IF NOT EXISTS idx_shoes_demo ON shoes(is_demo);

CREATE TABLE IF NOT EXISTS shoe_usage (
    shoe_id         TEXT NOT NULL REFERENCES shoes(id) ON DELETE CASCADE,
    workout_id      TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    distance_meters REAL NOT NULL,
    PRIMARY KEY (shoe_id, workout_id)
);

-- ---------- Personal records ----------

CREATE TABLE IF NOT EXISTS personal_records (
    athlete_id        TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    label             TEXT NOT NULL,                   -- 5K | 10K | Half | Full
    distance_meters   REAL NOT NULL,
    best_time_seconds INTEGER,
    achieved_at       INTEGER,
    workout_id        TEXT REFERENCES workouts(id) ON DELETE SET NULL,
    is_demo           INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (athlete_id, label)
);

CREATE INDEX IF NOT EXISTS idx_prs_demo ON personal_records(is_demo);

-- ---------- Streak + sweat points ----------

CREATE TABLE IF NOT EXISTS streaks (
    athlete_id               TEXT PRIMARY KEY REFERENCES athletes(id) ON DELETE CASCADE,
    current_days             INTEGER NOT NULL DEFAULT 0,
    longest_days             INTEGER NOT NULL DEFAULT 0,
    weekly_streak_weeks      INTEGER NOT NULL DEFAULT 0,
    at_risk_by_date          INTEGER,
    staked_sweat             INTEGER NOT NULL DEFAULT 0,
    stake_expires_at         INTEGER,
    multiplier               REAL NOT NULL DEFAULT 1.0,
    is_demo                  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sweat_points (
    athlete_id     TEXT PRIMARY KEY REFERENCES athletes(id) ON DELETE CASCADE,
    total          INTEGER NOT NULL DEFAULT 0,
    weekly         INTEGER NOT NULL DEFAULT 0,
    updated_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0
);

-- ---------- Metadata / admin ----------

CREATE TABLE IF NOT EXISTS schema_meta (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);

INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('version', '1');
INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('demo_seeded', '0');

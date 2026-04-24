-- Per-user UserProfile object ids the operator owns on-chain. One row
-- per athlete once they've had a profile minted. Indexer backfills this
-- on the first WorkoutSubmitted event for each athlete.

CREATE TABLE IF NOT EXISTS sui_user_profiles (
    athlete_id         TEXT PRIMARY KEY REFERENCES athletes(id) ON DELETE CASCADE,
    profile_object_id  TEXT NOT NULL,
    created_tx_digest  TEXT,
    created_at         INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_sui_profiles_object ON sui_user_profiles(profile_object_id);

-- Indexer cursor. One row, always keyed 'workouts_cursor'. Value is
-- the event cursor JSON Sui returned last tick; empty string = start
-- from the beginning.
INSERT OR IGNORE INTO schema_meta (key, value) VALUES ('sui_indexer_cursor', '');

-- Track raw on-chain events we've ingested so we can audit mismatches.
CREATE TABLE IF NOT EXISTS sui_events (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    event_seq          TEXT NOT NULL,
    tx_digest          TEXT NOT NULL,
    event_type         TEXT NOT NULL,         -- e.g. "0x...::rewards_engine::RewardMinted"
    athlete_id         TEXT,
    workout_object_id  TEXT,
    amount             INTEGER,
    raw                TEXT NOT NULL,          -- JSON of the event parsed_json field
    ingested_at        INTEGER NOT NULL DEFAULT (unixepoch()),
    UNIQUE (event_seq, tx_digest)
);

CREATE INDEX IF NOT EXISTS idx_events_athlete ON sui_events(athlete_id, ingested_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_type ON sui_events(event_type);

-- On the workouts table, carry the blob metadata + on-chain refs.
-- walrus_blob_id / sui_object_id / sui_tx_digest already exist from
-- migration 0001; we just add storage for the SWEAT amount minted.
ALTER TABLE workouts ADD COLUMN sweat_minted INTEGER NOT NULL DEFAULT 0;

-- App Attest keys registered by iOS clients. One row per key; counter is
-- updated on every assertion to prevent replay. When the app uninstalls
-- and reinstalls, a new keyId is generated.

CREATE TABLE IF NOT EXISTS app_attest_keys (
    key_id           TEXT PRIMARY KEY,            -- base64url of the attestation keyId
    athlete_id       TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    public_key_jwk   TEXT NOT NULL,               -- serialized JWK (EC P-256)
    counter          INTEGER NOT NULL DEFAULT 0,  -- last seen authData counter
    receipt          BLOB,                        -- Apple attestation receipt (for future fraud checks)
    cert_chain_ok    INTEGER NOT NULL DEFAULT 0,  -- 1 if we fully verified x5c against Apple root
    registered_at    INTEGER NOT NULL DEFAULT (unixepoch()),
    last_used_at     INTEGER
);

CREATE INDEX IF NOT EXISTS idx_attest_athlete ON app_attest_keys(athlete_id);

-- Nonces we issue for attestation. TTL = 5 minutes; consumed on first use.
CREATE TABLE IF NOT EXISTS attest_challenges (
    challenge       TEXT PRIMARY KEY,            -- base64url random 32 bytes
    athlete_id      TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    consumed        INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_challenges_athlete ON attest_challenges(athlete_id);

-- Suspicious activity log for anti-fraud review. No blocking yet — we
-- record and flag for manual inspection.
CREATE TABLE IF NOT EXISTS suspect_activity (
    id              TEXT PRIMARY KEY,
    athlete_id      TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    reason          TEXT NOT NULL,               -- "pace_impossible" | "velocity_exceeded" | "duplicate" | ...
    details         TEXT NOT NULL,               -- JSON of the offending payload
    created_at      INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_suspect_athlete ON suspect_activity(athlete_id, created_at DESC);

-- Dedup: compute SHA-256(canonicalized workout fields) and UNIQUE.
-- A resubmission with identical sensor data hits the unique constraint
-- and fails cleanly.
ALTER TABLE workouts ADD COLUMN canonical_hash TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_workouts_canonical_hash
    ON workouts(athlete_id, canonical_hash)
    WHERE canonical_hash IS NOT NULL;

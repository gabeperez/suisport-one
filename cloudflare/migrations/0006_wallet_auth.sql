-- Short-lived nonces used to prove ownership of a Sui address.
-- Flow: POST /v1/auth/wallet/challenge creates a row (5-min TTL).
-- User signs the nonce string with their Sui wallet's private key.
-- POST /v1/auth/wallet/verify consumes the row and issues a session
-- if the signature + public-key derived address match.
CREATE TABLE IF NOT EXISTS wallet_challenges (
    id              TEXT PRIMARY KEY,        -- uuid
    nonce           TEXT NOT NULL UNIQUE,    -- what the wallet signs
    created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    expires_at      INTEGER NOT NULL,
    consumed        INTEGER NOT NULL DEFAULT 0,
    consumed_addr   TEXT
);

CREATE INDEX IF NOT EXISTS idx_wallet_challenges_expires
    ON wallet_challenges(expires_at);

-- Rewards redemption (off-chain MVP).
--
-- Catalog of redeemable items (promo codes, gift card amounts, gear).
-- Admin-only writes; users read. Costs are in Sweat Points. `code_pool`
-- stores pre-generated redemption codes as a newline-separated string;
-- redeem pops the first line. When code_pool is empty the item is
-- auto-hidden from the catalog.
CREATE TABLE IF NOT EXISTS rewards_catalog (
    id            TEXT PRIMARY KEY,
    sku           TEXT NOT NULL UNIQUE,        -- internal identifier, e.g. "strava_1y_10off"
    title         TEXT NOT NULL,
    subtitle      TEXT,
    description   TEXT,
    image_url     TEXT,
    cost_points   INTEGER NOT NULL,
    code_pool     TEXT NOT NULL DEFAULT '',    -- newline-separated codes, one per redemption
    stock_total   INTEGER NOT NULL DEFAULT 0,  -- informational; authoritative truth is code_pool line count
    stock_claimed INTEGER NOT NULL DEFAULT 0,
    active        INTEGER NOT NULL DEFAULT 1,
    created_at    INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_rewards_catalog_active
ON rewards_catalog(active, cost_points);

-- One row per redemption. `code_revealed` is the specific code the user
-- gets — we store it server-side so redemptions are replayable if the
-- client crashes mid-reveal. The client can re-fetch via /rewards/history.
CREATE TABLE IF NOT EXISTS redemptions (
    id              TEXT PRIMARY KEY,
    athlete_id      TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    catalog_id      TEXT NOT NULL REFERENCES rewards_catalog(id),
    cost_points     INTEGER NOT NULL,
    code_revealed   TEXT NOT NULL,
    redeemed_at     INTEGER NOT NULL DEFAULT (unixepoch())
);

CREATE INDEX IF NOT EXISTS idx_redemptions_athlete
ON redemptions(athlete_id, redeemed_at DESC);

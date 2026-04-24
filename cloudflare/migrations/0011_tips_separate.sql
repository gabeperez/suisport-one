-- Separate tips from kudos.
--
-- Before this migration, tipping was entangled with kudos:
--   kudos (feed_item_id, athlete_id) UNIQUE with amount_sweat column
--   Toggling kudos off deleted the row → wiped the tip.
--   A 1-in-4 client-side die roll on tap added a random tip.
--
-- After: tips are an append-only ledger. Each tap inserts a row; a user
-- can tip the same feed item many times. Kudos is a pure "heart"
-- toggle with no payment semantics. feed_items.tipped_sweat stays as
-- the stored aggregate (now SUM over tips instead of kudos).

CREATE TABLE IF NOT EXISTS tips (
    id             TEXT PRIMARY KEY,
    feed_item_id   TEXT NOT NULL REFERENCES feed_items(id) ON DELETE CASCADE,
    athlete_id     TEXT NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    amount_sweat   INTEGER NOT NULL DEFAULT 1,
    created_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    is_demo        INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_tips_item    ON tips(feed_item_id);
CREATE INDEX IF NOT EXISTS idx_tips_athlete ON tips(athlete_id);

-- Backfill: every historic kudos row with amount_sweat > 0 becomes
-- a tip. Preserve the original created_at + is_demo flag.
INSERT INTO tips (id, feed_item_id, athlete_id, amount_sweat, created_at, is_demo)
SELECT 'mig_' || id, feed_item_id, athlete_id, amount_sweat, created_at, is_demo
FROM kudos
WHERE amount_sweat > 0;

-- Kudos is now pure; clear the amount column so future code can't
-- accidentally read it as authoritative. The column stays for schema
-- compatibility.
UPDATE kudos SET amount_sweat = 0 WHERE amount_sweat > 0;

-- Re-aggregate feed_items.tipped_sweat from the tips table so the
-- existing stored-aggregate approach keeps working after this
-- migration's backfill.
UPDATE feed_items
SET tipped_sweat = COALESCE(
    (SELECT SUM(amount_sweat) FROM tips WHERE feed_item_id = feed_items.id),
    0
);

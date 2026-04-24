-- Cache the SuiNS name owned by each athlete. Populated on sign-in
-- and refreshable on demand. NULL = no SuiNS name (or not yet resolved).

ALTER TABLE athletes ADD COLUMN suins_name TEXT;

CREATE INDEX IF NOT EXISTS idx_athletes_suins ON athletes(suins_name)
    WHERE suins_name IS NOT NULL;

-- Sweat ledger columns on the athletes table.
--
-- Two additive cumulative counters that let us power the on-device
-- breakdown sheet (Lifetime earned / Bonus earned / Already redeemed)
-- without scanning workouts + redemptions on every read.
--
--   sweat_credited — sum of `pointsMinted` (display units) across every
--                    successful chain mint. Includes server-formula
--                    bonuses (first-time, streak, multiplier).
--   sweat_redeemed — sum of `costPoints` across every successful
--                    redemption (sample tickets + catalog drops).
--
-- Both default to 0 so existing rows remain valid after the migration.
-- Worker increment statements are wrapped in try/catch so a deploy
-- without this migration applied stays safe (the increments fail
-- soft, and `/me` returns 0 instead of the column value).

ALTER TABLE athletes ADD COLUMN sweat_credited INTEGER NOT NULL DEFAULT 0;
ALTER TABLE athletes ADD COLUMN sweat_redeemed INTEGER NOT NULL DEFAULT 0;

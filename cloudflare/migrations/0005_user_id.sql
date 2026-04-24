-- The public, user-facing identity. A hex-16 UUID the server assigns at
-- signup. Immutable per athlete — username / handle / SuiNS / Sui
-- address can all change; user_id cannot. Everything the iOS app shows
-- as "this athlete" uses user_id; internal joins still key on
-- athletes.id (the Sui address) for FK simplicity in this pass.

ALTER TABLE athletes ADD COLUMN user_id TEXT;

UPDATE athletes
SET user_id = lower(hex(randomblob(16)))
WHERE user_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_athletes_user_id ON athletes(user_id);

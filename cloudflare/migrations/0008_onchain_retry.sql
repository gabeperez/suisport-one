-- Track on-chain retry state so the reconciler cron can surface
-- stuck workouts (sui_tx_digest LIKE 'pending_%') and back off
-- when Sui RPC is degraded instead of stampeding every minute.

ALTER TABLE workouts ADD COLUMN onchain_retry_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE workouts ADD COLUMN onchain_last_retry_at INTEGER;
ALTER TABLE workouts ADD COLUMN onchain_last_error TEXT;

CREATE INDEX IF NOT EXISTS idx_workouts_onchain_pending
ON workouts(sui_tx_digest, onchain_retry_count)
WHERE sui_tx_digest LIKE 'pending_%';

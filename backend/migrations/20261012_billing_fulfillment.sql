CREATE TABLE IF NOT EXISTS billing_grant_keys (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    grant_key TEXT NOT NULL,
    PRIMARY KEY(user_id,grant_key)
);
INSERT INTO billing_grant_keys(user_id,grant_key)
SELECT DISTINCT user_id,description FROM credit_transactions
WHERE amount>0 AND COALESCE(description,'')<>'' AND description<>'credits granted'
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS revenuecat_webhook_events (
    id TEXT PRIMARY KEY,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','completed')),
    attempts INTEGER NOT NULL DEFAULT 0,
    claimed_at TIMESTAMPTZ,
    retry_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_revenuecat_webhook_pending
    ON revenuecat_webhook_events(retry_at,created_at) WHERE status='pending';
ALTER TABLE billing_purchases ADD COLUMN IF NOT EXISTS store_transaction_id TEXT NOT NULL DEFAULT '';
ALTER TABLE billing_purchases ADD COLUMN IF NOT EXISTS fulfilled_at TIMESTAMPTZ;
-- Historical 'paid' rows are not proof of delivery: old code recorded them even
-- after a grant failed. Backfill only grants supported by an actual ledger row.
UPDATE billing_purchases p SET fulfilled_at=p.purchased_at
WHERE p.provider='revenuecat' AND p.fulfilled_at IS NULL AND EXISTS(
    SELECT 1 FROM credit_transactions t WHERE t.user_id=p.user_id AND t.amount>0
    AND t.description=(CASE WHEN p.kind='coin_pack' THEN 'rc-purchase:' ELSE 'rc-subscription:' END)||p.transaction_id
);
CREATE INDEX IF NOT EXISTS idx_billing_purchases_confirmation
    ON billing_purchases(user_id,provider,store_transaction_id);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS entitlement_ids JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS revenuecat_event_at_ms BIGINT NOT NULL DEFAULT 0;

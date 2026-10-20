ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS store TEXT NOT NULL DEFAULT '';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS period_type TEXT NOT NULL DEFAULT '';
-- Recover actual store names from completed, validated RevenueCat events.
WITH latest AS (
 SELECT DISTINCT ON (payload->>'original_transaction_id') payload
 FROM revenuecat_webhook_events WHERE status='completed'
 AND COALESCE(payload->>'original_transaction_id','')<>''
 AND COALESCE(payload->>'store','')<>''
 ORDER BY payload->>'original_transaction_id',COALESCE((payload->>'event_timestamp_ms')::bigint,0) DESC,created_at DESC
)
UPDATE subscriptions s SET store=UPPER(latest.payload->>'store'),period_type=UPPER(COALESCE(latest.payload->>'period_type',''))
FROM latest WHERE s.provider='revenuecat' AND s.provider_ref=latest.payload->>'original_transaction_id' AND s.store='';

-- Additive Web billing tables; existing App and Admin contracts remain valid.
CREATE TABLE IF NOT EXISTS paypal_checkouts (
 id TEXT PRIMARY KEY,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 request_key TEXT NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('coin','subscription')),
 product_key TEXT NOT NULL,
 product_id TEXT NOT NULL,
 paypal_plan_id TEXT NOT NULL DEFAULT '',
 amount_minor BIGINT NOT NULL CHECK(amount_minor > 0),
 coins INTEGER NOT NULL CHECK(coins >= 0),
 period TEXT NOT NULL DEFAULT '',
 provider_id TEXT UNIQUE,
 approval_url TEXT NOT NULL DEFAULT '',
 state TEXT NOT NULL DEFAULT 'created',
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(user_id,request_key)
);
CREATE INDEX IF NOT EXISTS paypal_checkouts_user ON paypal_checkouts(user_id,created_at DESC);
CREATE TABLE IF NOT EXISTS paypal_payments (
 transaction_id TEXT PRIMARY KEY,
 checkout_id TEXT NOT NULL REFERENCES paypal_checkouts(id) ON DELETE CASCADE,
 amount_minor BIGINT NOT NULL,
 paid_at TIMESTAMPTZ NOT NULL,
 refunded_minor BIGINT NOT NULL DEFAULT 0,
 reversed_coins INTEGER NOT NULL DEFAULT 0,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS paypal_webhook_events (
 id TEXT PRIMARY KEY,
 event_type TEXT NOT NULL,
 processed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS paypal_refunds (
 id TEXT PRIMARY KEY,
 transaction_id TEXT NOT NULL REFERENCES paypal_payments(transaction_id) ON DELETE CASCADE,
 amount_minor BIGINT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

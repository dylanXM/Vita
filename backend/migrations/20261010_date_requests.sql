CREATE TABLE IF NOT EXISTS companion_date_requests (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
    product_key TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    scheduled_at TIMESTAMP NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('requested','accepted','declined','payment_required','failed')),
    reason TEXT NOT NULL DEFAULT '',
    event_id TEXT NOT NULL DEFAULT '',
    result JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id,idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_companion_date_requests_companion
    ON companion_date_requests(companion_id,created_at DESC);

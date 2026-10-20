ALTER TABLE ai_pet_states
    ADD COLUMN IF NOT EXISTS hydration INTEGER NOT NULL DEFAULT 80
    CHECK (hydration BETWEEN 0 AND 100);

CREATE TABLE IF NOT EXISTS ai_pet_care_events (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('pet','drink','walk','rest')),
    request_key TEXT NOT NULL,
    result JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, request_key)
);

CREATE INDEX IF NOT EXISTS idx_ai_pet_care_events_cooldown
    ON ai_pet_care_events(companion_id, kind, created_at DESC);

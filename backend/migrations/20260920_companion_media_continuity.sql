BEGIN;

ALTER TABLE agent_settings
    ADD COLUMN IF NOT EXISTS image_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS daily_life_photo_limit INTEGER NOT NULL DEFAULT 2,
    ADD COLUMN IF NOT EXISTS transcription_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS speech_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL;

ALTER TABLE memories
    ADD COLUMN IF NOT EXISTS follow_up_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS follow_up_claimed_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS followed_up_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_memories_follow_up
    ON memories(follow_up_at)
    WHERE followed_up_at IS NULL;

CREATE TABLE IF NOT EXISTS pending_agent_replies (
    conversation_id TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
    trigger_message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    scheduled_at TIMESTAMP NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_pending_agent_replies_due
    ON pending_agent_replies(status, scheduled_at);

CREATE TABLE IF NOT EXISTS media_assets (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('image', 'audio')),
    mime_type TEXT NOT NULL,
    data BYTEA NOT NULL,
    size_bytes INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_media_assets_user
    ON media_assets(user_id, created_at DESC);

COMMIT;

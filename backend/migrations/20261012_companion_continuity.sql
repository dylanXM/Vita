ALTER TABLE memories ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','resolved','cancelled','superseded'));
ALTER TABLE memories ADD COLUMN IF NOT EXISTS source_message_id TEXT;
CREATE INDEX IF NOT EXISTS idx_memories_active ON memories(companion_id,created_at DESC) WHERE status='active';

CREATE TABLE IF NOT EXISTS companion_memory_jobs (
    message_id TEXT PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed','failed')),
    attempts INTEGER NOT NULL DEFAULT 0,
    claimed_at TIMESTAMP,
    retry_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_contact_preferences (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    daily_limit INTEGER NOT NULL CHECK (daily_limit BETWEEN 0 AND 8),
    minimum_gap_minutes INTEGER NOT NULL CHECK (minimum_gap_minutes BETWEEN 30 AND 1440),
    quiet_enabled BOOLEAN NOT NULL,
    quiet_start INTEGER NOT NULL CHECK (quiet_start BETWEEN 0 AND 23),
    quiet_end INTEGER NOT NULL CHECK (quiet_end BETWEEN 0 AND 23),
    CHECK (NOT quiet_enabled OR quiet_start<>quiet_end)
);

INSERT INTO agent_media_routes(route_key,media_type,enabled) VALUES ('text_memory','text',false)
ON CONFLICT(route_key) DO NOTHING;

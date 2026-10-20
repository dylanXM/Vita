ALTER TABLE conversations ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_conversations_user_companion
    ON conversations(user_id, companion_id);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
    ON messages(conversation_id, created_at DESC);

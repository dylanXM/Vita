CREATE INDEX IF NOT EXISTS idx_conversations_user_companion ON conversations(user_id,companion_id,id);
CREATE INDEX IF NOT EXISTS idx_messages_latest_notification ON messages(conversation_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS idx_messages_unread_notification ON messages(conversation_id,created_at) WHERE sender_type='assistant';

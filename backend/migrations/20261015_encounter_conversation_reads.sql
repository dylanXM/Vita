-- Existing conversations start read; newly delivered messages become unread.
ALTER TABLE encounter_conversations
 ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 ADD COLUMN IF NOT EXISTS last_read_message_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000';

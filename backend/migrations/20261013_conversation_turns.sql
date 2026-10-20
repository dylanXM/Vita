ALTER TABLE conversations ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS companion_conversation_queue (
 id TEXT PRIMARY KEY,
 conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
 trigger_message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
 ordinal INTEGER NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('burst','followup')),
 content TEXT NOT NULL,
 payload JSONB NOT NULL DEFAULT '{}',
 due_at TIMESTAMPTZ NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL,
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','processing','sent','cancelled')),
 attempts INTEGER NOT NULL DEFAULT 0,
 claimed_at TIMESTAMPTZ,
 last_error TEXT NOT NULL DEFAULT '',
 UNIQUE(trigger_message_id,kind,ordinal)
);
CREATE INDEX IF NOT EXISTS companion_conversation_queue_due ON companion_conversation_queue(kind,due_at) WHERE status='pending';

CREATE TABLE encounter_characters (
 id UUID PRIMARY KEY, owner_id UUID REFERENCES users(id) ON DELETE CASCADE,
 name TEXT NOT NULL, gender TEXT NOT NULL CHECK (gender IN ('male','female','other')),
 personality TEXT NOT NULL DEFAULT '', persona TEXT NOT NULL DEFAULT '',
 description TEXT NOT NULL DEFAULT '', cover_url TEXT NOT NULL, avatar_url TEXT NOT NULL DEFAULT '',
 enabled BOOLEAN NOT NULL DEFAULT TRUE, sort_order INTEGER NOT NULL DEFAULT 0,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE encounter_preferences (
 user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 gender TEXT NOT NULL DEFAULT '', personality TEXT NOT NULL DEFAULT ''
);
CREATE TABLE encounter_conversations (
 id UUID PRIMARY KEY, user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 character_id UUID NOT NULL REFERENCES encounter_characters(id),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(user_id,character_id)
);
CREATE TABLE encounter_requests (
 id UUID PRIMARY KEY, conversation_id UUID NOT NULL REFERENCES encounter_conversations(id) ON DELETE CASCADE,
 request_key TEXT NOT NULL, content TEXT NOT NULL, product_key TEXT NOT NULL DEFAULT '',
 quoted_coins INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'processing'
 CHECK(status IN ('processing','completed','failed')), spend_id UUID REFERENCES credit_spends(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(conversation_id,request_key)
);
CREATE TABLE encounter_messages (
 id UUID PRIMARY KEY, conversation_id UUID NOT NULL REFERENCES encounter_conversations(id) ON DELETE CASCADE,
 request_id UUID NOT NULL REFERENCES encounter_requests(id), sender_type TEXT NOT NULL,
 content TEXT NOT NULL DEFAULT '', media_url TEXT NOT NULL DEFAULT '',
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(request_id,sender_type)
);
CREATE INDEX encounter_messages_history ON encounter_messages(conversation_id,created_at,id);
CREATE INDEX encounter_conversations_user ON encounter_conversations(user_id,updated_at DESC);

CREATE TABLE IF NOT EXISTS companion_affect (
 companion_id TEXT PRIMARY KEY REFERENCES companions(id) ON DELETE CASCADE,
 version BIGINT NOT NULL DEFAULT 0,
 feeling TEXT NOT NULL DEFAULT 'neutral',
 reason TEXT NOT NULL DEFAULT '',
 action TEXT NOT NULL DEFAULT 'open',
 contact_after TIMESTAMPTZ,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS companion_affect_events (
 companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
 cause TEXT NOT NULL,
 effect JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(companion_id,cause)
);
CREATE TABLE IF NOT EXISTS companion_contact_decisions (
 event_id TEXT PRIMARY KEY REFERENCES life_events(id) ON DELETE CASCADE,
 attempts INTEGER NOT NULL DEFAULT 1,
 resolved BOOLEAN NOT NULL DEFAULT false,
 attempted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS companion_affect_interpersonal_history
 ON companion_affect_events(companion_id,created_at DESC)
 WHERE cause NOT LIKE 'life:%';

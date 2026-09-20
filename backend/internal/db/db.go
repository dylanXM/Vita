package db

import (
	"database/sql"
	"fmt"
	_ "github.com/lib/pq"
	"vita/internal/config"
)

var _db *sql.DB

func Open(cfg *config.Config) (*sql.DB, error) {
	db, err := sql.Open("postgres", cfg.DBDSN)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)

	if cfg.AutoMigrate {
		if err := migrate(db); err != nil {
			return nil, fmt.Errorf("migration failed: %w", err)
		}
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("database ping failed: %w", err)
	}

	_db = db
	fmt.Println("database connected successfully")
	return db, nil
}

func Close() {
	if _db != nil {
		_db.Close()
	}
}

func Get() *sql.DB {
	return _db
}

func migrate(db *sql.DB) error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS roles (
			id TEXT PRIMARY KEY,
			name TEXT UNIQUE NOT NULL,
			description TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS users (
			id TEXT PRIMARY KEY,
			email TEXT UNIQUE NOT NULL,
			role_id TEXT NOT NULL DEFAULT 'user',
			password_hash TEXT NOT NULL DEFAULT '',
			timezone TEXT DEFAULT 'UTC',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS verification_codes (
			id TEXT PRIMARY KEY,
			email TEXT NOT NULL,
			code TEXT NOT NULL,
			purpose TEXT NOT NULL DEFAULT 'login',
			expires_at TIMESTAMP NOT NULL,
			used BOOLEAN DEFAULT false,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_verification_codes_email ON verification_codes(email)`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS banned BOOLEAN NOT NULL DEFAULT false`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS credits_balance INTEGER NOT NULL DEFAULT 0`,
		// Environment the account registered on (dev | beta | prod). Beta and
		// prod share one database, so the flag lives on the row, not per-server.
		// Existing rows predate the flag — they are live production accounts.
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS environment TEXT NOT NULL DEFAULT 'prod'`,
		`CREATE INDEX IF NOT EXISTS idx_users_environment ON users(environment)`,
		`CREATE INDEX IF NOT EXISTS idx_verification_codes_expires ON verification_codes(expires_at)`,
		`CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)`,
		`CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at)`,
		`CREATE TABLE IF NOT EXISTS credit_transactions (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			amount INTEGER NOT NULL,
			balance_after INTEGER NOT NULL,
			kind TEXT NOT NULL DEFAULT 'grant',
			description TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_credit_transactions_user ON credit_transactions(user_id, created_at DESC)`,
		`CREATE TABLE IF NOT EXISTS subscriptions (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			provider TEXT NOT NULL,
			provider_ref TEXT NOT NULL,
			app_user_id TEXT,
			product_id TEXT,
			entitlement TEXT,
			status TEXT NOT NULL DEFAULT 'active',
			current_period_start TIMESTAMP,
			current_period_end TIMESTAMP,
			will_renew BOOLEAN DEFAULT true,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_provider_ref ON subscriptions(provider, provider_ref)`,
		`CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id)`,
		`CREATE TABLE IF NOT EXISTS companions (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			name TEXT NOT NULL,
			gender TEXT,
			persona TEXT,
			appearance TEXT,
			city TEXT,
			occupation TEXT,
			interests TEXT,
			relationship_stage TEXT DEFAULT 'stranger',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS conversations (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id),
			companion_id TEXT NOT NULL REFERENCES companions(id),
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS messages (
			id TEXT PRIMARY KEY,
			conversation_id TEXT NOT NULL REFERENCES conversations(id),
			sender_type TEXT NOT NULL,
			message_type TEXT DEFAULT 'text',
			content TEXT,
			media_url TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS memories (
			id TEXT PRIMARY KEY,
			companion_id TEXT NOT NULL REFERENCES companions(id),
			type TEXT,
			content TEXT,
			importance INTEGER DEFAULT 0,
			event_time TIMESTAMP,
			embedding TEXT,
			metadata TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS life_events (
			id TEXT PRIMARY KEY,
			companion_id TEXT NOT NULL REFERENCES companions(id),
			event_type TEXT,
			title TEXT,
			description TEXT,
			location TEXT,
			start_time TIMESTAMP,
			end_time TIMESTAMP,
			emotion TEXT,
			importance INTEGER DEFAULT 0,
			user_relevance INTEGER DEFAULT 0,
			shareability BOOLEAN DEFAULT false,
			status TEXT DEFAULT 'active'
		)`,
		`CREATE TABLE IF NOT EXISTS relationship_states (
			companion_id TEXT PRIMARY KEY REFERENCES companions(id),
			intimacy INTEGER DEFAULT 0,
			trust INTEGER DEFAULT 0,
			familiarity INTEGER DEFAULT 0,
			shared_history TEXT,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS companion_states (
			companion_id TEXT PRIMARY KEY REFERENCES companions(id),
			mood INTEGER DEFAULT 50,
			energy INTEGER DEFAULT 50,
			stress INTEGER DEFAULT 50,
			social_energy INTEGER DEFAULT 50,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS ai_providers (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			kind TEXT NOT NULL CHECK (kind IN ('openai', 'anthropic')),
			base_url TEXT NOT NULL,
			api_key_ciphertext TEXT NOT NULL DEFAULT '',
			enabled BOOLEAN NOT NULL DEFAULT true,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS ai_models (
			id TEXT PRIMARY KEY,
			provider_id TEXT NOT NULL REFERENCES ai_providers(id) ON DELETE CASCADE,
			model_name TEXT NOT NULL,
			display_name TEXT NOT NULL,
			capabilities JSONB NOT NULL DEFAULT '["text"]'::jsonb,
			enabled BOOLEAN NOT NULL DEFAULT true,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(provider_id, model_name)
		)`,
		`CREATE TABLE IF NOT EXISTS agent_settings (
			id TEXT PRIMARY KEY DEFAULT 'default',
			chat_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			life_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			proactive_model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			daily_event_min INTEGER NOT NULL DEFAULT 8,
			daily_event_max INTEGER NOT NULL DEFAULT 15,
			daily_proactive_limit INTEGER NOT NULL DEFAULT 4,
			quiet_hours_start INTEGER NOT NULL DEFAULT 23,
			quiet_hours_end INTEGER NOT NULL DEFAULT 8,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`INSERT INTO agent_settings (id) VALUES ('default') ON CONFLICT (id) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS companion_portraits (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			image_url TEXT NOT NULL,
			gender TEXT NOT NULL DEFAULT 'custom',
			personality_tags JSONB NOT NULL DEFAULT '[]'::jsonb,
			enabled BOOLEAN NOT NULL DEFAULT true,
			sort_order INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`INSERT INTO companion_portraits (id,name,image_url,gender,personality_tags,enabled,sort_order) VALUES
			('system-mia','Mia','asset://assets/companions/mia.png','girlfriend','["warm","independent","thoughtful"]'::jsonb,true,10),
			('system-nora','Nora','asset://assets/companions/nora.png','girlfriend','["witty","curious","outgoing"]'::jsonb,true,20),
			('system-leo','Leo','asset://assets/companions/leo.png','boyfriend','["calm","creative","independent"]'::jsonb,true,30),
			('system-kai','Kai','asset://assets/companions/kai.png','boyfriend','["thoughtful","playful","ambitious"]'::jsonb,true,40)
		ON CONFLICT (id) DO UPDATE SET image_url=EXCLUDED.image_url, personality_tags=EXCLUDED.personality_tags`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS personality_tags JSONB NOT NULL DEFAULT '[]'::jsonb`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS speaking_style TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS likes TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS dislikes TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS life_habits TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS life_goal TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS backstory TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS portrait_id TEXT REFERENCES companion_portraits(id) ON DELETE SET NULL`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS creation_source TEXT NOT NULL DEFAULT 'tags_portrait'`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS proactive_enabled BOOLEAN NOT NULL DEFAULT true`,
		`ALTER TABLE companions ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'user'`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS life_event_id TEXT`,
		`ALTER TABLE messages ADD COLUMN IF NOT EXISTS delivery_status TEXT NOT NULL DEFAULT 'delivered'`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS local_date DATE`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS sequence INTEGER NOT NULL DEFAULT 0`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS generation_source TEXT NOT NULL DEFAULT 'agent'`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS shared_at TIMESTAMP`,
		`ALTER TABLE life_events ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_life_events_day_sequence ON life_events(companion_id, local_date, sequence) WHERE local_date IS NOT NULL`,
		`CREATE INDEX IF NOT EXISTS idx_life_events_due ON life_events(start_time, shareability, shared_at)`,
		`CREATE TABLE IF NOT EXISTS companion_days (
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			local_date DATE NOT NULL,
			timezone TEXT NOT NULL DEFAULT 'UTC',
			status TEXT NOT NULL DEFAULT 'pending',
			event_count INTEGER NOT NULL DEFAULT 0,
			generated_at TIMESTAMP,
			last_error TEXT NOT NULL DEFAULT '',
			PRIMARY KEY(companion_id, local_date)
		)`,
		`CREATE TABLE IF NOT EXISTS notification_outbox (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			companion_id TEXT NOT NULL REFERENCES companions(id) ON DELETE CASCADE,
			message_id TEXT REFERENCES messages(id) ON DELETE CASCADE,
			channel TEXT NOT NULL DEFAULT 'push',
			payload JSONB NOT NULL DEFAULT '{}'::jsonb,
			status TEXT NOT NULL DEFAULT 'pending',
			attempts INTEGER NOT NULL DEFAULT 0,
			available_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			sent_at TIMESTAMP,
			last_error TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_outbox_message_channel ON notification_outbox(message_id, channel)`,
		`ALTER TABLE notification_outbox ALTER COLUMN channel SET DEFAULT 'push'`,
		`CREATE TABLE IF NOT EXISTS device_push_tokens (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			token TEXT NOT NULL UNIQUE,
			platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
			device_id TEXT NOT NULL DEFAULT '',
			locale TEXT NOT NULL DEFAULT '',
			enabled BOOLEAN NOT NULL DEFAULT true,
			last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE INDEX IF NOT EXISTS idx_device_push_tokens_user ON device_push_tokens(user_id, enabled)`,
		`CREATE TABLE IF NOT EXISTS agent_runs (
			id TEXT PRIMARY KEY,
			companion_id TEXT REFERENCES companions(id) ON DELETE SET NULL,
			kind TEXT NOT NULL,
			model_id TEXT REFERENCES ai_models(id) ON DELETE SET NULL,
			status TEXT NOT NULL,
			input_summary TEXT NOT NULL DEFAULT '',
			error TEXT NOT NULL DEFAULT '',
			started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			finished_at TIMESTAMP
		)`,
		`INSERT INTO roles (id, name, description) VALUES ('user', 'user', 'Regular user') ON CONFLICT (id) DO NOTHING`,
		`INSERT INTO roles (id, name, description) VALUES ('admin', 'admin', 'Administrator') ON CONFLICT (id) DO NOTHING`,
	}

	for _, q := range queries {
		preview := q
		if len(preview) > 60 {
			preview = preview[:60]
		}
		fmt.Printf("Executing migration: %s...\n", preview)
		if _, err := db.Exec(q); err != nil {
			return fmt.Errorf("failed to execute: %w", err)
		}
	}
	return nil
}

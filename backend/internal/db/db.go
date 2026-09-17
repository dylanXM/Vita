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
		`CREATE INDEX IF NOT EXISTS idx_verification_codes_expires ON verification_codes(expires_at)`,
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
		`INSERT INTO roles (id, name, description) VALUES ('user', 'user', 'Regular user') ON CONFLICT (id) DO NOTHING`,
		`INSERT INTO roles (id, name, description) VALUES ('admin', 'admin', 'Administrator') ON CONFLICT (id) DO NOTHING`,
	}

	for _, q := range queries {
		fmt.Printf("Executing migration: %s...\n", q[:60])
		if _, err := db.Exec(q); err != nil {
			return fmt.Errorf("failed to execute: %w", err)
		}
	}
	return nil
}

package db

import (
	"context"
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
	"github.com/lib/pq"
	"vita/internal/config"
)

var _db *sql.DB

func Open(cfg *config.Config) (*sql.DB, error) {
	var db *sql.DB
	var err error

	if cfg.DBDriver == "sqlite" {
		db, err = sql.Open("sqlite", cfg.DBDSN)
	} else {
		db, err = sql.Open("postgres", cfg.DBDSN)
	}
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

func migrate(db *sql.DB) error {
	// Create essential tables for Vita AI Companion
	queries := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id TEXT PRIMARY KEY,
			email TEXT UNIQUE NOT NULL,
			password_hash TEXT,
			timezone TEXT DEFAULT 'UTC',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)`,
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
	}

	for _, q := range queries {
		if _, err := db.Exec(q); err != nil {
			return fmt.Errorf("failed to execute: %w", err)
		}
	}
	return nil
}

func Close() {
	if _db != nil {
		_db.Close()
	}
}

func Get() *sql.DB {
	return _db
}

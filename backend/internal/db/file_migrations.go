package db

import (
	"crypto/sha256"
	"database/sql"
	"fmt"
	"io/fs"
	"sort"
	"strings"

	"vita/migrations"
)

// Existing SQL files through this name are handled by the legacy inline schema.
const lastInlineMigration = "20261009_ai_pet_care.sql"

var inlineMigrationFiles = map[string]struct{}{
	"20260920_billing_product_catalog.sql":    {},
	"20260920_chat_list_latest_message.sql":   {},
	"20260920_companion_media_continuity.sql": {},
	"20260920_credit_experiences.sql":         {},
	"20260920_legal_consent.sql":              {},
	"20260920_legal_documents.sql":            {},
	"20260920_media_model_routes.sql":         {},
	"20260920_model_scenarios.sql":            {},
	"20260920_model_subscription_plans.sql":   {},
	"20260920_text_model_routes.sql":          {},
	"20260921_ai_pets.sql":                    {},
	"20260921_character_creation.sql":         {},
	"20260921_companion_soft_delete.sql":      {},
	"20260921_media_storage.sql":              {},
	"20260921_story_hub.sql":                  {},
	"20261008_ai_pet_pose_sheets.sql":         {},
	"20261009_ai_pet_care.sql":                {},
}

func migrateFiles(db *sql.DB, verbose bool) error {
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
		name TEXT PRIMARY KEY,
		checksum TEXT NOT NULL,
		applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
	)`); err != nil {
		return fmt.Errorf("create migration history: %w", err)
	}

	entries, err := fs.ReadDir(migrations.Files, ".")
	if err != nil {
		return fmt.Errorf("list SQL migrations: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasSuffix(name, ".sql") {
			continue
		}
		if _, historical := inlineMigrationFiles[name]; historical {
			continue
		}
		if name <= lastInlineMigration {
			return fmt.Errorf("new migration %s must sort after %s", name, lastInlineMigration)
		}
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		content, err := migrations.Files.ReadFile(name)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", name, err)
		}
		checksum := fmt.Sprintf("%x", sha256.Sum256(content))
		var recorded string
		err = db.QueryRow(`SELECT checksum FROM schema_migrations WHERE name=$1`, name).Scan(&recorded)
		if err == nil {
			if recorded != checksum {
				return fmt.Errorf("migration %s changed after application", name)
			}
			continue
		}
		if err != sql.ErrNoRows {
			return fmt.Errorf("check migration %s: %w", name, err)
		}
		tx, err := db.Begin()
		if err != nil {
			return fmt.Errorf("begin migration %s: %w", name, err)
		}
		if _, err = tx.Exec(string(content)); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("apply migration %s: %w", name, err)
		}
		if _, err = tx.Exec(`INSERT INTO schema_migrations(name,checksum) VALUES($1,$2)`, name, checksum); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("record migration %s: %w", name, err)
		}
		if err = tx.Commit(); err != nil {
			return fmt.Errorf("commit migration %s: %w", name, err)
		}
		if verbose {
			fmt.Printf("Applied SQL migration: %s\n", name)
		}
	}
	return nil
}

package main

import (
	"database/sql"
	"log"
	"os"
	"strings"

	_ "github.com/lib/pq"

	"vita/internal/db"
)

func main() {
	dsn := strings.TrimSpace(os.Getenv("VITA_DB_DSN"))
	if dsn == "" || strings.Contains(strings.ToLower(dsn), "placeholder") || strings.Contains(strings.ToLower(dsn), "user:password@db-host") {
		log.Fatal("VITA_DB_DSN must be set to a non-placeholder PostgreSQL DSN")
	}
	database, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer database.Close()
	if err := database.Ping(); err != nil {
		log.Fatalf("ping database: %v", err)
	}
	if err := db.Migrate(database); err != nil {
		log.Fatalf("apply migrations: %v", err)
	}
	log.Println("database migrations completed")
}

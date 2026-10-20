package main

import (
	"context"
	"database/sql"
	"log"
	"os"
	"time"

	_ "github.com/lib/pq"

	"vita/internal/storage"
)

func main() {
	dsn := os.Getenv("VITA_DB_DSN")
	key := os.Getenv("VITA_AGENT_CONFIG_KEY")
	if dsn == "" || key == "" {
		log.Fatal("VITA_DB_DSN and VITA_AGENT_CONFIG_KEY are required")
	}
	database, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer database.Close()
	if err := database.Ping(); err != nil {
		log.Fatal(err)
	}
	service, err := storage.NewService(database, "prod", key)
	if err != nil {
		log.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Hour)
	defer cancel()
	if err := service.MigrateLegacyMedia(ctx); err != nil {
		log.Fatal(err)
	}
	log.Println("legacy media copied to prod storage; run the database migration before starting the new backend")
}

package config

import (
	"strings"
	"testing"
	"time"
)

func validProductionConfig() *Config {
	return &Config{
		Env:            EnvProd,
		DBDSN:          "postgres://vita:secret@db.internal:5432/vita?sslmode=require",
		RedisURL:       "rediss://:secret@redis.internal:6379/0",
		JWTSecret:      strings.Repeat("j", 32),
		JWTTTL:         15 * time.Minute,
		JWTRefreshTTL:  30 * 24 * time.Hour,
		AgentConfigKey: strings.Repeat("a", 32),
		AllowedOrigins: []string{"https://admin.vita.example"},
		SMTPHost:       "smtp.example.com",
		SMTPUsername:   "mailer",
		SMTPPassword:   "secret",
		SMTPFrom:       "no-reply@example.com",
	}
}

func TestValidateProductionConfig(t *testing.T) {
	if err := validProductionConfig().Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestValidateRejectsProductionPlaceholders(t *testing.T) {
	cfg := validProductionConfig()
	cfg.JWTSecret = "replace-with-production-secret-value"
	if err := cfg.Validate(); err == nil {
		t.Fatal("placeholder JWT secret was accepted")
	}
}

func TestValidateRejectsInvalidRedisURL(t *testing.T) {
	cfg := validProductionConfig()
	cfg.RedisURL = "redis.internal:6379"
	if err := cfg.Validate(); err == nil {
		t.Fatal("invalid Redis URL was accepted")
	}
}

func TestValidateRejectsSharedSecretsAndWildcardOrigins(t *testing.T) {
	cfg := validProductionConfig()
	cfg.AgentConfigKey = cfg.JWTSecret
	if err := cfg.Validate(); err == nil {
		t.Fatal("shared JWT and agent secrets were accepted")
	}
	cfg = validProductionConfig()
	cfg.AllowedOrigins = []string{"*"}
	if err := cfg.Validate(); err == nil {
		t.Fatal("wildcard CORS origin was accepted")
	}
}

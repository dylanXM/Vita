package config

import (
	"fmt"
	"os"
	"strings"
	"time"
)

type Config struct {
	Env              string
	HTTPAddr         string
	DBDriver         string
	DBDSN            string
	RedisURL         string
	RedisPassword    string
	JWTSecret        string
	JWTTTL           time.Duration
	MockGeneration   bool
	AutoMigrate      bool
	StorageProvider  string
	S3Bucket         string
	S3Endpoint       string
	S3AccessKey      string
	S3SecretKey      string
	ServerPort       string

	// AdminEmail + AdminPassword seed the initial administrator account on
	// startup (see db.EnsureAdmin). AdminEmails is the comma-separated
	// allowlist of accounts that get the admin role without having their
	// password managed here.
	AdminEmail    string
	AdminPassword string
	AdminEmails   []string
}

func Load() *Config {
	return &Config{
		Env:             getEnv("TOVIDEO_ENV", "dev"),
		HTTPAddr:        getEnv("TOVIDEO_HTTP_ADDR", ":8080"),
		DBDriver:        getEnv("TOVIDEO_DB_DRIVER", "postgres"),
		DBDSN:           getEnv("TOVIDEO_DB_DSN", "postgres://tovideo:tovideo_dev_password@127.0.0.1:5433/vita?sslmode=disable"),
		RedisURL:        getEnv("TOVIDEO_REDIS_URL", "redis://localhost:6380/0"),
		RedisPassword:   getEnv("REDIS_PASSWORD", ""),
		JWTSecret:       getEnv("TOVIDEO_JWT_SECRET", "dev-secret-change-me-32-characters-min"),
		JWTTTL:          24 * time.Hour,
		MockGeneration:  getEnv("TOVIDEO_MOCK_GENERATION", "true") == "true",
		AutoMigrate:     getEnv("TOVIDEO_AUTO_MIGRATE", "true") == "true",
		StorageProvider: getEnv("TOVIDEO_STORAGE_PROVIDER", "s3"),
		S3Bucket:        getEnv("TOVIDEO_S3_BUCKET", "vita-media"),
		S3Endpoint:      getEnv("TOVIDEO_S3_ENDPOINT", "http://rustfs:9000"),
		S3AccessKey:     getEnv("TOVIDEO_S3_ACCESS_KEY", "vita_rustfs"),
		S3SecretKey:     getEnv("TOVIDEO_S3_SECRET_KEY", "vita_rustfs_secret"),
		ServerPort:      getEnv("SERVER_PORT", "8080"),

		AdminEmail:    getEnv("TOVIDEO_ADMIN_EMAIL", ""),
		AdminPassword: getEnv("TOVIDEO_ADMIN_PASSWORD", ""),
		AdminEmails:   splitCSV(getEnv("TOVIDEO_ADMIN_EMAILS", "")),
	}
}

func splitCSV(raw string) []string {
	var out []string
	for _, part := range strings.Split(raw, ",") {
		if v := strings.TrimSpace(part); v != "" {
			out = append(out, v)
		}
	}
	return out
}

func getEnv(key, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return defaultVal
}

func (c *Config) Validate() error {
	if c.JWTSecret == "" {
		return fmt.Errorf("TOVIDEO_JWT_SECRET is required")
	}
	return nil
}

package config

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// Deployment environments. Every account is stamped with the environment of
// the server it registered on, so one shared database (beta and prod point at
// the same instance) can tell pre-release test accounts apart from live ones.
const (
	EnvDev  = "dev"  // local development
	EnvBeta = "beta" // pre-release; the beta backend runs against the prod database
	EnvProd = "prod" // production
)

// IsValidEnvironment reports whether env is one of the three known deployments.
func IsValidEnvironment(env string) bool {
	switch env {
	case EnvDev, EnvBeta, EnvProd:
		return true
	}
	return false
}

type Config struct {
	Env             string
	HTTPAddr        string
	DBDriver        string
	DBDSN           string
	RedisURL        string
	RedisPassword   string
	JWTSecret       string
	JWTTTL          time.Duration
	JWTRefreshTTL   time.Duration
	AllowedOrigins  []string
	MockGeneration  bool
	AutoMigrate     bool
	StorageProvider string
	S3Bucket        string
	S3Endpoint      string
	S3AccessKey     string
	S3SecretKey     string
	ServerPort      string

	// AdminEmail + AdminPassword seed the initial administrator account on
	// startup (see db.EnsureAdmin). AdminEmails is the comma-separated
	// allowlist of accounts that get the admin role without having their
	// password managed here.
	AdminEmail    string
	AdminPassword string
	AdminEmails   []string

	// GoogleClientID is the OAuth 2.0 client ID used to verify Google ID
	// tokens from the mobile app (self-hosted OIDC, no Firebase).
	GoogleClientID string

	// SMTP settings for outbound verification-code email (VITA_SMTP_*).
	// Host empty = dev mode, codes are printed to the server log instead.
	SMTPHost     string
	SMTPPort     int
	SMTPUsername string
	SMTPPassword string
	SMTPFrom     string
	SMTPFromName string

	// AgentConfigKey encrypts provider API keys stored through the admin UI.
	AgentConfigKey               string
	AgentEnabled                 bool
	AgentTick                    time.Duration
	FirebaseProjectID            string
	FirebaseServiceAccountBase64 string

	// RevenueCatWebhookSecret verifies the Authorization header on the
	// RevenueCat webhook (the "Shared Secret" shown in the RC dashboard).
	RevenueCatWebhookSecret string

	// Stripe keys. SecretKey is used to call the Stripe REST API (no SDK
	// dependency); WebhookSecret verifies Stripe webhook signatures.
	StripeSecretKey     string
	StripeWebhookSecret string

	// SubscriptionCreditsMonthly is granted on each subscription purchase /
	// renewal (credits model, see the monetisation plan).
	SubscriptionCreditsMonthly int
}

func Load() *Config {
	return &Config{
		Env:             strings.ToLower(getEnv("VITA_ENV", EnvDev)),
		HTTPAddr:        getEnv("VITA_HTTP_ADDR", ":8080"),
		DBDriver:        getEnv("VITA_DB_DRIVER", "postgres"),
		DBDSN:           getEnv("VITA_DB_DSN", "postgres://tovideo:tovideo_dev_password@127.0.0.1:5433/vita?sslmode=disable"),
		RedisURL:        getEnv("VITA_REDIS_URL", "redis://localhost:6380/0"),
		RedisPassword:   getEnv("REDIS_PASSWORD", ""),
		JWTSecret:       getEnv("VITA_JWT_SECRET", "dev-secret-change-me-32-characters-min"),
		JWTTTL:          durationEnv(getEnv("VITA_JWT_ACCESS_TTL", "15m"), 15*time.Minute),
		JWTRefreshTTL:   durationEnv(getEnv("VITA_JWT_REFRESH_TTL", "720h"), 30*24*time.Hour),
		AllowedOrigins:  splitCSV(getEnv("VITA_ALLOWED_ORIGINS", "http://localhost:8261,http://localhost:8263")),
		MockGeneration:  getEnv("VITA_MOCK_GENERATION", "true") == "true",
		AutoMigrate:     getEnv("VITA_AUTO_MIGRATE", "true") == "true",
		StorageProvider: getEnv("VITA_STORAGE_PROVIDER", "s3"),
		S3Bucket:        getEnv("VITA_S3_BUCKET", "vita-media"),
		S3Endpoint:      getEnv("VITA_S3_ENDPOINT", "http://rustfs:9000"),
		S3AccessKey:     getEnv("VITA_S3_ACCESS_KEY", "vita_rustfs"),
		S3SecretKey:     getEnv("VITA_S3_SECRET_KEY", "vita_rustfs_secret"),
		ServerPort:      getEnv("SERVER_PORT", "8080"),

		AdminEmail:    getEnv("VITA_ADMIN_EMAIL", ""),
		AdminPassword: getEnv("VITA_ADMIN_PASSWORD", ""),
		AdminEmails:   splitCSV(getEnv("VITA_ADMIN_EMAILS", "")),

		GoogleClientID: getEnv("VITA_GOOGLE_CLIENT_ID", ""),

		SMTPHost:     getEnv("VITA_SMTP_HOST", ""),
		SMTPPort:     atoiEnv(getEnv("VITA_SMTP_PORT", "465"), 465),
		SMTPUsername: getEnv("VITA_SMTP_USERNAME", ""),
		SMTPPassword: getEnv("VITA_SMTP_PASSWORD", ""),
		SMTPFrom:     getEnv("VITA_SMTP_FROM", ""),
		SMTPFromName: getEnv("VITA_SMTP_FROM_NAME", "Vita"),

		AgentConfigKey:               getEnv("VITA_AGENT_CONFIG_KEY", "dev-agent-config-key-32-characters-min"),
		AgentEnabled:                 getEnv("VITA_AGENT_ENABLED", "true") == "true",
		AgentTick:                    durationEnv(getEnv("VITA_AGENT_TICK", "1m"), time.Minute),
		FirebaseProjectID:            getEnv("VITA_FIREBASE_PROJECT_ID", ""),
		FirebaseServiceAccountBase64: getEnv("VITA_FIREBASE_SERVICE_ACCOUNT_BASE64", ""),

		RevenueCatWebhookSecret: getEnv("VITA_REVENUECAT_WEBHOOK_SECRET", ""),

		StripeSecretKey:     getEnv("VITA_STRIPE_SECRET_KEY", ""),
		StripeWebhookSecret: getEnv("VITA_STRIPE_WEBHOOK_SECRET", ""),

		SubscriptionCreditsMonthly: atoiEnv(getEnv("VITA_SUBSCRIPTION_CREDITS_MONTHLY", "500"), 500),
	}
}

func atoiEnv(raw string, fallback int) int {
	if v, err := strconv.Atoi(raw); err == nil {
		return v
	}
	return fallback
}

func durationEnv(raw string, fallback time.Duration) time.Duration {
	if value, err := time.ParseDuration(raw); err == nil && value > 0 {
		return value
	}
	return fallback
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
	if !IsValidEnvironment(c.Env) {
		return fmt.Errorf("VITA_ENV must be one of dev, beta or prod")
	}
	if len(c.JWTSecret) < 32 {
		return fmt.Errorf("VITA_JWT_SECRET must contain at least 32 characters")
	}
	if c.JWTTTL <= 0 || c.JWTRefreshTTL <= c.JWTTTL {
		return fmt.Errorf("VITA_JWT_REFRESH_TTL must be greater than VITA_JWT_ACCESS_TTL")
	}
	redisURL, err := url.Parse(c.RedisURL)
	if err != nil || (redisURL.Scheme != "redis" && redisURL.Scheme != "rediss") || redisURL.Host == "" {
		return fmt.Errorf("VITA_REDIS_URL must be a valid redis:// or rediss:// URL")
	}
	if c.Env == EnvBeta || c.Env == EnvProd {
		for name, value := range map[string]string{
			"VITA_DB_DSN":           c.DBDSN,
			"VITA_JWT_SECRET":       c.JWTSecret,
			"VITA_AGENT_CONFIG_KEY": c.AgentConfigKey,
		} {
			if isPlaceholder(value) {
				return fmt.Errorf("%s must be set to a non-placeholder production value", name)
			}
		}
		if len(c.AgentConfigKey) < 32 {
			return fmt.Errorf("VITA_AGENT_CONFIG_KEY must contain at least 32 characters")
		}
		if c.AgentConfigKey == c.JWTSecret {
			return fmt.Errorf("VITA_AGENT_CONFIG_KEY must be different from VITA_JWT_SECRET")
		}
		if len(c.AllowedOrigins) == 0 {
			return fmt.Errorf("VITA_ALLOWED_ORIGINS is required outside dev")
		}
		for _, origin := range c.AllowedOrigins {
			parsed, err := url.Parse(origin)
			if err != nil || parsed.Scheme != "https" || parsed.Host == "" || strings.Contains(origin, "*") {
				return fmt.Errorf("VITA_ALLOWED_ORIGINS entries must be explicit HTTPS origins")
			}
		}
		if c.SMTPHost == "" || c.SMTPUsername == "" || c.SMTPPassword == "" || c.SMTPFrom == "" {
			return fmt.Errorf("VITA_SMTP_HOST, VITA_SMTP_USERNAME, VITA_SMTP_PASSWORD and VITA_SMTP_FROM are required outside dev")
		}
	}
	return nil
}

func isPlaceholder(value string) bool {
	value = strings.ToLower(strings.TrimSpace(value))
	return value == "" || strings.Contains(value, "replace-with") || strings.Contains(value, "placeholder") || strings.Contains(value, "user:password@db-host")
}

package handler

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"vita/internal/agent"
	"vita/internal/auth"
	"vita/internal/config"
	"vita/internal/db"
	"vita/internal/language"
	"vita/internal/mail"
	"vita/internal/storage"
)

const codeLength = 6
const codeTTL = 5 * time.Minute

var rdb *redis.Client
var tokenManager *auth.TokenManager

// envName is the deployment environment this server runs in (VITA_ENV: dev /
// beta / prod). Accounts created while it is set get stamped with this value
// so a shared database can separate pre-release accounts from live ones.
var envName = config.EnvDev

// SetEnvironment records the deployment environment (called from main).
// Unknown values are rejected with a warning — silently relabelling a
// mistyped VITA_ENV would stamp accounts with the wrong environment flag.
func SetEnvironment(env string) {
	if config.IsValidEnvironment(env) {
		envName = env
		return
	}
	fmt.Printf("warning: VITA_ENV=%q is not one of dev/beta/prod; accounts will be stamped %q\n", env, envName)
}

// mailCfg is the SMTP client used to deliver verification codes. A zero
// value (dev) prints codes to the server log instead.
var mailCfg = mail.Config{}

// InitMailer configures outbound verification-code email (VITA_SMTP_*).
func InitMailer(cfg mail.Config) {
	mailCfg = cfg
}

// currentEnvironment returns the environment stamped onto new accounts. It
// is always one of dev/beta/prod: envName starts at the default and is only
// ever replaced with a validated value (see SetEnvironment).
func currentEnvironment() string {
	return envName
}

func InitRedis(redisURL, passwordOverride string) (*redis.Client, error) {
	options, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, fmt.Errorf("parse Redis URL: %w", err)
	}
	if passwordOverride != "" {
		options.Password = passwordOverride
	}
	client := redis.NewClient(options)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("ping Redis: %w", err)
	}
	rdb = client
	return client, nil
}

func InitAuth(manager *auth.TokenManager) {
	tokenManager = manager
}

type HealthResponse struct {
	Status  string `json:"status"`
	Version string `json:"version"`
}

func Health(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
	defer cancel()
	if database := db.Get(); database == nil || database.PingContext(ctx) != nil {
		c.JSON(http.StatusServiceUnavailable, HealthResponse{Status: "database_unavailable", Version: "0.1.0"})
		return
	}
	if rdb == nil || rdb.Ping(ctx).Err() != nil {
		c.JSON(http.StatusServiceUnavailable, HealthResponse{Status: "redis_unavailable", Version: "0.1.0"})
		return
	}
	c.JSON(http.StatusOK, HealthResponse{Status: "ok", Version: "0.1.0"})
}

// --- Verification Code ---

type SendCodeRequest struct {
	Email                string `json:"email" binding:"required,email"`
	Purpose              string `json:"purpose"`
	AcceptedLegal        *bool  `json:"accepted_legal"`
	PrivacyPolicyVersion string `json:"privacy_policy_version"`
	TermsVersion         string `json:"terms_version"`
}

type SendCodeResponse struct {
	Message string `json:"message"`
}

func SendCode(c *gin.Context) {
	var req SendCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if user exists (for login), or create new user (for register)
	var userID, userRole string
	err := db.Get().QueryRow(`SELECT id, COALESCE(role_id, 'user') FROM users WHERE email = $1`, req.Email).Scan(&userID, &userRole)
	if errors.Is(err, sql.ErrNoRows) {
		acceptedAt, consentErr := legalAcceptance(req.AcceptedLegal, req.PrivacyPolicyVersion, req.TermsVersion)
		if consentErr != nil {
			writeLegalAcceptanceError(c, consentErr)
			return
		}
		// A verification-code client may register only after explicit consent.
		userID = uuid.New().String()
		_, err = db.Get().Exec(`INSERT INTO users (id,email,role_id,environment,legal_accepted_at,privacy_policy_version,terms_version)
			VALUES ($1,$2,'user',$3,$4,$5,$6)`, userID, req.Email, currentEnvironment(), acceptedAt,
			strings.TrimSpace(req.PrivacyPolicyVersion), strings.TrimSpace(req.TermsVersion))
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
			return
		}
		userRole = "user"
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		return
	}

	// Generate verification code
	code, err := generateCode()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate verification code"})
		return
	}
	expiresAt := time.Now().Add(codeTTL)

	// Store code in Redis with expiration
	ctx := context.Background()
	codeData := map[string]string{
		"email":   req.Email,
		"user_id": userID,
		"role":    userRole,
		"purpose": req.Purpose,
	}
	codeJSON, _ := json.Marshal(codeData)
	err = rdb.Set(ctx, verificationCodeKey(req.Email, code), string(codeJSON), codeTTL).Err()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store verification code"})
		return
	}

	// Also store in DB for backup
	codeID := uuid.New().String()
	_, err = db.Get().Exec(`INSERT INTO verification_codes (id, email, code, purpose, expires_at) VALUES ($1, $2, $3, $4, $5)`,
		codeID, req.Email, code, req.Purpose, expiresAt)
	if err != nil {
		// Non-fatal, Redis is the primary store
	}

	// Send the code by email (dev: printed to the server log)
	if err := mailCfg.SendVerificationCode(req.Email, code); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to send verification code"})
		return
	}

	c.JSON(http.StatusOK, SendCodeResponse{Message: "Verification code sent"})
}

func generateCode() (string, error) {
	value, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", value.Int64()), nil
}

func verificationCodeKey(email, code string) string {
	return "vcode:" + strings.ToLower(strings.TrimSpace(email)) + ":" + code
}

// --- Auth Routes ---

type RegisterRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type RegisterResponse struct {
	UserID string `json:"user_id"`
	TokenResponse
}

func Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if user exists
	var exists bool
	err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)`, req.Email).Scan(&exists)
	if err != nil || exists {
		c.JSON(http.StatusConflict, gin.H{"error": "email already exists"})
		return
	}

	userID := uuid.New().String()
	_, err = db.Get().Exec(`INSERT INTO users (id, email, role_id, environment) VALUES ($1, $2, 'user', $3)`, userID, req.Email, currentEnvironment())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	tokens, err := issueTokens(userID, "user")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}
	c.JSON(http.StatusCreated, RegisterResponse{UserID: userID, TokenResponse: tokens})
}

type LoginRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code" binding:"required,len=6"`
}

type LoginResponse struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
	TokenResponse
}

func Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify code from Redis
	ctx := context.Background()
	codeDataJSON, err := rdb.Get(ctx, verificationCodeKey(req.Email, req.Code)).Result()
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired verification code"})
		return
	}

	var codeData map[string]string
	if err := json.Unmarshal([]byte(codeDataJSON), &codeData); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid verification code"})
		return
	}

	// Verify email matches
	if !strings.EqualFold(codeData["email"], req.Email) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "verification code does not match this email"})
		return
	}

	// Mark code as used (delete from Redis)
	rdb.Del(ctx, verificationCodeKey(req.Email, req.Code))

	// Mark as used in DB
	_, _ = db.Get().Exec(`UPDATE verification_codes SET used = true WHERE code = $1 AND email = $2`, req.Code, req.Email)

	userID := codeData["user_id"]
	userRole := codeData["role"]

	// Get user ID if we only have email
	if userID == "" {
		err = db.Get().QueryRow(`SELECT id FROM users WHERE email = $1`, req.Email).Scan(&userID)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
			return
		}
	}

	if banned, err := userBanned(userID); err == nil && banned {
		c.JSON(http.StatusForbidden, gin.H{"error": "account is banned"})
		return
	}

	tokens, err := issueTokens(userID, userRole)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, LoginResponse{UserID: userID, Role: userRole, TokenResponse: tokens})
}

// AdminLogin - admin sign-in for the dashboard. Accepts either an
// email + password (the initial administrator credential, see db.EnsureAdmin)
// or email + 6-digit verification code (the account-recovery path used by the
// rest of the API). Both require the admin role.
type AdminLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password"`
	Code     string `json:"code"`
}

type AdminLoginResponse struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
	TokenResponse
}

func AdminLogin(c *gin.Context) {
	var req AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var userID string
	switch {
	case req.Password != "":
		id, err := userIDByPassword(req.Email, req.Password)
		if err != nil {
			// Deliberately one message for both causes so the endpoint does not
			// reveal whether an email is registered.
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid email or password"})
			return
		}
		userID = id
	case len(req.Code) == 6:
		id, err := consumeVerificationCode(req.Email, req.Code)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
			return
		}
		userID = id
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "password or 6-digit verification code is required"})
		return
	}

	// Check if user has admin role
	var role string
	err := db.Get().QueryRow(`SELECT COALESCE(role_id, 'user') FROM users WHERE id = $1`, userID).Scan(&role)
	if err != nil || role != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "admin access required"})
		return
	}

	tokens, err := issueTokens(userID, "admin")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, AdminLoginResponse{UserID: userID, Role: "admin", TokenResponse: tokens})
}

// userIDByPassword resolves an account by email and checks its bcrypt hash.
func userIDByPassword(email, password string) (string, error) {
	var id, hash string
	err := db.Get().QueryRow(
		`SELECT id, COALESCE(password_hash, '') FROM users WHERE email = $1`, email).Scan(&id, &hash)
	if err != nil {
		return "", errors.New("invalid email or password")
	}
	if !auth.VerifyPassword(hash, password) {
		return "", errors.New("invalid email or password")
	}
	return id, nil
}

// consumeVerificationCode validates a 6-digit code and returns the user id it
// was issued for, marking the code used.
func consumeVerificationCode(email, code string) (string, error) {
	ctx := context.Background()
	codeDataJSON, err := rdb.Get(ctx, verificationCodeKey(email, code)).Result()
	if err != nil {
		return "", errors.New("invalid or expired verification code")
	}

	var codeData map[string]string
	if err := json.Unmarshal([]byte(codeDataJSON), &codeData); err != nil {
		return "", errors.New("invalid verification code")
	}

	if !strings.EqualFold(codeData["email"], email) {
		return "", errors.New("verification code does not match this email")
	}

	rdb.Del(ctx, verificationCodeKey(email, code))
	_, _ = db.Get().Exec(`UPDATE verification_codes SET used = true WHERE code = $1 AND email = $2`, code, email)

	if userID := codeData["user_id"]; userID != "" {
		return userID, nil
	}

	var userID string
	if err := db.Get().QueryRow(`SELECT id FROM users WHERE email = $1`, email).Scan(&userID); err != nil {
		return "", errors.New("user not found")
	}
	return userID, nil
}

// --- Admin Environment ---

type AdminEnvironmentResponse struct {
	Environment string `json:"environment"`
}

// AdminEnvironment reports which deployment this API instance is running in.
// The dashboard shows it in the system card and uses it as the default
// environment for newly created user accounts.
func AdminEnvironment(c *gin.Context) {
	c.JSON(http.StatusOK, AdminEnvironmentResponse{Environment: currentEnvironment()})
}

// --- Current Account ---

type ProfileResponse struct {
	UserID     string    `json:"user_id"`
	Email      string    `json:"email"`
	Role       string    `json:"role"`
	Timezone   string    `json:"timezone"`
	InviteCode string    `json:"invite_code"`
	Locale     string    `json:"locale"`
	CreatedAt  time.Time `json:"created_at"`
}

// Me returns the account behind the bearer token. The dashboard uses it both to
// rehydrate a stored session on reload and to confirm the account is an admin.
func Me(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	var p ProfileResponse
	err := db.Get().QueryRow(
		`SELECT id, email, COALESCE(role_id, 'user'), COALESCE(timezone, 'UTC'), invite_code, preferred_locale, created_at FROM users WHERE id = $1`,
		userID).Scan(&p.UserID, &p.Email, &p.Role, &p.Timezone, &p.InviteCode, &p.Locale, &p.CreatedAt)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "account not found"})
		return
	}

	c.JSON(http.StatusOK, p)
}

// DeleteMe permanently removes the signed-in regular account and its owned
// content. Billing provider records are removed locally; store subscriptions
// must still be cancelled by the user in Apple/Google account settings.
func DeleteMe(c *gin.Context) {
	userID := c.GetString("user_id")
	var email, role string
	if err := db.Get().QueryRow(`SELECT email,COALESCE(role_id,'user') FROM users WHERE id=$1`, userID).Scan(&email, &role); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
		return
	}
	if role == "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "administrator accounts cannot be deleted here"})
		return
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start account deletion"})
		return
	}
	defer tx.Rollback() //nolint:errcheck
	steps := []struct {
		query string
		args  []any
	}{
		{`DELETE FROM invitation_rewards WHERE inviter_user_id=$1 OR invited_user_id=$1`, []any{userID}},
		{`DELETE FROM billing_purchases WHERE user_id=$1`, []any{userID}},
		{`DELETE FROM subscriptions WHERE user_id=$1`, []any{userID}},
		{`DELETE FROM credit_transactions WHERE user_id=$1`, []any{userID}},
		{`DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id=$1)`, []any{userID}},
		{`DELETE FROM conversations WHERE user_id=$1`, []any{userID}},
		{`DELETE FROM memories WHERE companion_id IN (SELECT id FROM companions WHERE user_id=$1)`, []any{userID}},
		{`DELETE FROM life_events WHERE companion_id IN (SELECT id FROM companions WHERE user_id=$1)`, []any{userID}},
		{`DELETE FROM relationship_states WHERE companion_id IN (SELECT id FROM companions WHERE user_id=$1)`, []any{userID}},
		{`DELETE FROM companion_states WHERE companion_id IN (SELECT id FROM companions WHERE user_id=$1)`, []any{userID}},
		{`DELETE FROM companions WHERE user_id=$1`, []any{userID}},
		{`DELETE FROM verification_codes WHERE email=$1`, []any{email}},
		{`DELETE FROM users WHERE id=$1`, []any{userID}},
	}
	for _, step := range steps {
		if _, err := tx.ExecContext(c.Request.Context(), step.query, step.args...); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete account data"})
			return
		}
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to finish account deletion"})
		return
	}
	if sessionID := c.GetString("session_id"); sessionID != "" {
		_ = rdb.Set(c.Request.Context(), "vita:session:revoked:"+sessionID, "1", tokenManager.RefreshTTL()).Err()
	}
	c.JSON(http.StatusOK, gin.H{"message": "account deleted"})
}

func UpdateMyLocale(c *gin.Context) {
	var input struct {
		Locale string `json:"locale" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "locale is required"})
		return
	}
	locale := language.Normalize(input.Locale)
	if _, err := db.Get().Exec(`UPDATE users SET preferred_locale=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2`, locale, c.GetString("user_id")); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update locale"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"locale": locale})
}

// --- Admin Stats ---

type AdminStatsResponse struct {
	TotalUsers         int       `json:"total_users"`
	AdminUsers         int       `json:"admin_users"`
	NewUsers7d         int       `json:"new_users_7d"`
	TotalCompanions    int       `json:"total_companions"`
	NewCompanions7d    int       `json:"new_companions_7d"`
	TotalConversations int       `json:"total_conversations"`
	NewConversations7d int       `json:"new_conversations_7d"`
	TotalMessages      int       `json:"total_messages"`
	NewMessages7d      int       `json:"new_messages_7d"`
	TotalMemories      int       `json:"total_memories"`
	TotalLifeEvents    int       `json:"total_life_events"`
	TodayLifeEvents    int       `json:"today_life_events"`
	GeneratedAt        time.Time `json:"generated_at"`
}

// AdminStats powers the dashboard tiles. Everything is counted straight from
// the live tables in one round trip — no cached or estimated figures.
func AdminStats(c *gin.Context) {
	var s AdminStatsResponse
	err := db.Get().QueryRow(`
		SELECT
			(SELECT COUNT(*) FROM users),
			(SELECT COUNT(*) FROM users WHERE role_id = 'admin'),
			(SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '7 days'),
			(SELECT COUNT(*) FROM companions),
			(SELECT COUNT(*) FROM companions WHERE created_at >= NOW() - INTERVAL '7 days'),
			(SELECT COUNT(*) FROM conversations),
			(SELECT COUNT(*) FROM conversations WHERE created_at >= NOW() - INTERVAL '7 days'),
			(SELECT COUNT(*) FROM messages),
			(SELECT COUNT(*) FROM messages WHERE created_at >= NOW() - INTERVAL '7 days'),
			(SELECT COUNT(*) FROM memories),
			(SELECT COUNT(*) FROM life_events),
			(SELECT COUNT(*) FROM life_events WHERE DATE(start_time) = CURRENT_DATE)
	`).Scan(
		&s.TotalUsers, &s.AdminUsers, &s.NewUsers7d,
		&s.TotalCompanions, &s.NewCompanions7d,
		&s.TotalConversations, &s.NewConversations7d,
		&s.TotalMessages, &s.NewMessages7d,
		&s.TotalMemories,
		&s.TotalLifeEvents, &s.TodayLifeEvents,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to collect stats"})
		return
	}

	s.GeneratedAt = time.Now().UTC()
	c.JSON(http.StatusOK, s)
}

// AppLogin - login endpoint for mobile app (email + password)
type AppLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type AppLoginResponse struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
	TokenResponse
}

func AppLogin(c *gin.Context) {
	var req AppLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var userID, hash, role string
	err := db.Get().QueryRow(
		`SELECT id, COALESCE(password_hash, ''), COALESCE(role_id, 'user') FROM users WHERE email = $1`,
		req.Email).Scan(&userID, &hash, &role)
	if err != nil || !auth.VerifyPassword(hash, req.Password) {
		// One message for both causes so the endpoint does not reveal whether
		// an email is registered.
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid email or password"})
		return
	}

	if banned, err := userBanned(userID); err == nil && banned {
		c.JSON(http.StatusForbidden, gin.H{"error": "account is banned"})
		return
	}

	tokens, err := issueTokens(userID, role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, AppLoginResponse{UserID: userID, Role: role, TokenResponse: tokens})
}

// --- App Registration (email + password + verification code) ---

const registerCooldown = 60 * time.Second

const pendingRegPrefix = "vita:reg:"

type pendingRegistration struct {
	PasswordHash         string     `json:"password_hash"`
	LegalAcceptedAt      *time.Time `json:"legal_accepted_at,omitempty"`
	PrivacyPolicyVersion string     `json:"privacy_policy_version,omitempty"`
	TermsVersion         string     `json:"terms_version,omitempty"`
}

func registrationLegalAcceptance(value *bool) (*time.Time, error) {
	if value == nil || !*value {
		return nil, errLegalConsentRequired
	}
	now := time.Now().UTC()
	return &now, nil
}

type AppRegisterRequest struct {
	Email                string `json:"email" binding:"required,email"`
	Password             string `json:"password" binding:"required,min=6"`
	InviteCode           string `json:"invite_code"`
	AcceptedLegal        *bool  `json:"accepted_legal"`
	PrivacyPolicyVersion string `json:"privacy_policy_version"`
	TermsVersion         string `json:"terms_version"`
}

type AppRegisterVerifyRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code" binding:"required,len=6"`
}

// AppRegister starts the registration flow: checks the email is free, stores
// the (hashed) password pending verification and emails a 6-digit code.
// Resending within 60s is rejected to limit mail abuse.
func AppRegister(c *gin.Context) {
	var req AppRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	acceptedAt, err := legalAcceptance(req.AcceptedLegal, req.PrivacyPolicyVersion, req.TermsVersion)
	if err != nil {
		writeLegalAcceptanceError(c, err)
		return
	}

	ctx := context.Background()
	cooldownKey := "vcode:cooldown:" + req.Email
	if rdb.Exists(ctx, cooldownKey).Val() > 0 {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "please wait 60 seconds before requesting another code"})
		return
	}

	var exists bool
	err = db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)`, req.Email).Scan(&exists)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check email"})
		return
	}
	if exists {
		c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
		return
	}
	req.InviteCode = strings.ToUpper(strings.TrimSpace(req.InviteCode))
	inviterID := ""
	if req.InviteCode != "" {
		err = db.Get().QueryRow(`SELECT id FROM users WHERE invite_code=$1 AND environment=$2`, req.InviteCode, currentEnvironment()).Scan(&inviterID)
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invitation code"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to validate invitation code"})
			return
		}
	}

	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register"})
		return
	}

	// Remember the password and consent until the code is verified.
	pendingKey := pendingRegPrefix + req.Email
	pending := pendingRegistration{PasswordHash: hash, LegalAcceptedAt: acceptedAt,
		PrivacyPolicyVersion: strings.TrimSpace(req.PrivacyPolicyVersion), TermsVersion: strings.TrimSpace(req.TermsVersion)}
	pendingJSON, _ := json.Marshal(pending)
	if err := rdb.Set(ctx, pendingKey, pendingJSON, codeTTL).Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start registration"})
		return
	}

	code, err := generateCode()
	if err != nil {
		rdb.Del(ctx, pendingKey)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate verification code"})
		return
	}
	codeJSON, _ := json.Marshal(map[string]string{
		"email":      req.Email,
		"purpose":    "register",
		"inviter_id": inviterID,
	})
	if err := rdb.Set(ctx, verificationCodeKey(req.Email, code), string(codeJSON), codeTTL).Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send verification code"})
		return
	}
	rdb.Set(ctx, cooldownKey, "1", registerCooldown)

	if err := mailCfg.SendVerificationCode(req.Email, code); err != nil {
		// Roll back so the user can retry immediately.
		rdb.Del(ctx, pendingKey, verificationCodeKey(req.Email, code), cooldownKey)
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to send verification code"})
		return
	}

	c.JSON(http.StatusOK, SendCodeResponse{Message: "Verification code sent"})
}

// AppRegisterVerify completes registration: validates the 6-digit code, creates
// the account with the pending password and issues the session token.
func AppRegisterVerify(c *gin.Context) {
	var req AppRegisterVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()
	codeDataJSON, err := rdb.Get(ctx, verificationCodeKey(req.Email, req.Code)).Result()
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired verification code"})
		return
	}
	var codeData map[string]string
	if err := json.Unmarshal([]byte(codeDataJSON), &codeData); err != nil ||
		!strings.EqualFold(codeData["email"], req.Email) || codeData["purpose"] != "register" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid verification code"})
		return
	}

	pendingKey := pendingRegPrefix + req.Email
	pendingRaw, err := rdb.Get(ctx, pendingKey).Result()
	if err != nil || pendingRaw == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "registration expired, please request a new code"})
		return
	}
	var pending pendingRegistration
	if err := json.Unmarshal([]byte(pendingRaw), &pending); err != nil {
		// Finish a verification already issued by an older Backend during a
		// rolling deployment; new registration requests are strictly gated above.
		pending.PasswordHash = pendingRaw
	}
	if pending.PasswordHash == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "registration expired, please request a new code"})
		return
	}

	var exists bool
	err = db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)`, req.Email).Scan(&exists)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}
	if exists {
		c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
		return
	}

	userID := uuid.New().String()
	var inviterID any
	if codeData["inviter_id"] != "" {
		var valid bool
		if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE id=$1 AND environment=$2)`, codeData["inviter_id"], currentEnvironment()).Scan(&valid); err != nil || !valid {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invitation code is no longer valid"})
			return
		}
		inviterID = codeData["inviter_id"]
	}
	if _, err := db.Get().Exec(
		`INSERT INTO users (id,email,role_id,password_hash,environment,invited_by_user_id,legal_accepted_at,privacy_policy_version,terms_version)
		 VALUES ($1,$2,'user',$3,$4,$5,$6,$7,$8)`,
		userID, req.Email, pending.PasswordHash, currentEnvironment(), inviterID, pending.LegalAcceptedAt,
		pending.PrivacyPolicyVersion, pending.TermsVersion); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	// Consume the code and the pending registration.
	rdb.Del(ctx, verificationCodeKey(req.Email, req.Code), pendingKey, "vcode:cooldown:"+req.Email)
	_, _ = db.Get().Exec(
		`INSERT INTO verification_codes (id, email, code, purpose, expires_at, used) VALUES ($1, $2, $3, 'register', $4, true)`,
		uuid.New().String(), req.Email, req.Code, time.Now().Add(codeTTL))

	tokens, err := issueTokens(userID, "user")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, AppLoginResponse{UserID: userID, Role: "user", TokenResponse: tokens})
}

// WebappLogin - login endpoint for web app
type WebappLoginRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code" binding:"required,len=6"`
}

type WebappLoginResponse struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
	TokenResponse
}

func WebappLogin(c *gin.Context) {
	var req WebappLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()
	codeDataJSON, err := rdb.Get(ctx, verificationCodeKey(req.Email, req.Code)).Result()
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired verification code"})
		return
	}

	var codeData map[string]string
	if err := json.Unmarshal([]byte(codeDataJSON), &codeData); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid verification code"})
		return
	}

	if !strings.EqualFold(codeData["email"], req.Email) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "verification code does not match this email"})
		return
	}

	rdb.Del(ctx, verificationCodeKey(req.Email, req.Code))
	_, _ = db.Get().Exec(`UPDATE verification_codes SET used = true WHERE code = $1 AND email = $2`, req.Code, req.Email)

	userID := codeData["user_id"]
	if userID == "" {
		err = db.Get().QueryRow(`SELECT id FROM users WHERE email = $1`, req.Email).Scan(&userID)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
			return
		}
	}

	if banned, err := userBanned(userID); err == nil && banned {
		c.JSON(http.StatusForbidden, gin.H{"error": "account is banned"})
		return
	}

	var role string
	err = db.Get().QueryRow(`SELECT role_id FROM users WHERE id = $1`, userID).Scan(&role)
	if err != nil {
		role = "user"
	}

	tokens, err := issueTokens(userID, role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, WebappLoginResponse{UserID: userID, Role: role, TokenResponse: tokens})
}

type LogoutResponse struct {
	Message string `json:"message"`
}

func Logout(c *gin.Context) {
	sessionID := c.GetString("session_id")
	if sessionID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}
	if err := rdb.Set(c.Request.Context(), "vita:session:revoked:"+sessionID, "1", tokenManager.RefreshTTL()).Err(); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "failed to revoke session"})
		return
	}
	c.JSON(http.StatusOK, LogoutResponse{Message: "logged out"})
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func RefreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "refresh_token is required"})
		return
	}
	claims, err := tokenManager.Parse(req.RefreshToken, auth.TokenTypeRefresh)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired refresh token"})
		return
	}
	ctx := c.Request.Context()
	revoked, err := rdb.Exists(ctx, "vita:session:revoked:"+claims.SessionID).Result()
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "session store unavailable"})
		return
	}
	if revoked > 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "session has been revoked"})
		return
	}
	remaining := time.Until(claims.ExpiresAt.Time)
	if remaining <= 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "refresh token expired"})
		return
	}
	used, err := rdb.SetNX(ctx, "vita:refresh:used:"+claims.ID, "1", remaining).Result()
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "session store unavailable"})
		return
	}
	if !used {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "refresh token has already been used"})
		return
	}
	if err := rdb.Set(ctx, "vita:session:revoked:"+claims.SessionID, "1", remaining).Err(); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "failed to rotate session"})
		return
	}
	var role string
	if err := db.Get().QueryRow(`SELECT COALESCE(role_id,'user') FROM users WHERE id=$1 AND banned=false`, claims.UserID).Scan(&role); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "account is unavailable"})
		return
	}
	tokens, err := issueTokens(claims.UserID, role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}
	c.JSON(http.StatusOK, tokens)
}

// --- Companion Routes ---

type Companion struct {
	ID                   string     `json:"id"`
	UserID               string     `json:"user_id"`
	Name                 string     `json:"name"`
	Gender               string     `json:"gender"`
	Persona              string     `json:"persona"`
	Appearance           string     `json:"appearance"`
	City                 string     `json:"city"`
	Occupation           string     `json:"occupation"`
	Interests            string     `json:"interests"`
	RelationshipStage    string     `json:"relationship_stage"`
	PersonalityTags      []string   `json:"personality_tags"`
	SpeakingStyle        string     `json:"speaking_style"`
	Likes                string     `json:"likes"`
	Dislikes             string     `json:"dislikes"`
	LifeHabits           string     `json:"life_habits"`
	LifeGoal             string     `json:"life_goal"`
	Backstory            string     `json:"backstory"`
	PortraitID           *string    `json:"portrait_id"`
	PortraitURL          string     `json:"portrait_url"`
	ModelID              *string    `json:"model_id"`
	CreationSource       string     `json:"creation_source"`
	ProactiveEnabled     bool       `json:"proactive_enabled"`
	Active               bool       `json:"active"`
	IsDefault            bool       `json:"is_default"`
	LifeEnabled          bool       `json:"life_enabled"`
	FriendshipActive     bool       `json:"friendship_active"`
	CanChat              bool       `json:"can_chat"`
	RequiresSubscription bool       `json:"requires_subscription"`
	TrialExpiresAt       *time.Time `json:"trial_expires_at,omitempty"`
	LastMessage          string     `json:"last_message,omitempty"`
	LastMessageType      string     `json:"last_message_type,omitempty"`
	LastMessageAt        *time.Time `json:"last_message_at,omitempty"`
	UnreadCount          int        `json:"unread_count"`
	CreatedAt            time.Time  `json:"created_at"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

type CreateCompanionRequest struct {
	Name              string   `json:"name" binding:"required"`
	Gender            string   `json:"gender"`
	Persona           string   `json:"persona"`
	Appearance        string   `json:"appearance"`
	City              string   `json:"city"`
	Occupation        string   `json:"occupation"`
	Interests         string   `json:"interests"`
	RelationshipStage string   `json:"relationship_stage"`
	PersonalityTags   []string `json:"personality_tags"`
	SpeakingStyle     string   `json:"speaking_style"`
	Likes             string   `json:"likes"`
	Dislikes          string   `json:"dislikes"`
	LifeHabits        string   `json:"life_habits"`
	LifeGoal          string   `json:"life_goal"`
	Backstory         string   `json:"backstory"`
	PortraitID        *string  `json:"portrait_id"`
	AvatarMediaID     *string  `json:"avatar_media_id"`
	CreationSource    string   `json:"creation_source"`
}

func CreateCompanion(c *gin.Context) {
	var req CreateCompanionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	companionID := uuid.New().String()
	userID := c.GetString("user_id")
	subscribed, err := userHasActiveSubscription(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check subscription"})
		return
	}
	if !subscribed {
		subscriptionRequired(c, "companion_creation_requires_subscription", "Subscribe to create your own companion")
		return
	}
	if len(req.PersonalityTags) > 8 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "choose no more than 8 personality tags"})
		return
	}
	if req.RelationshipStage == "" {
		req.RelationshipStage = "stranger"
	}
	creationSource := strings.TrimSpace(req.CreationSource)
	if creationSource == "" {
		creationSource = "tags_portrait"
	}
	if creationSource != "tags_portrait" && creationSource != "user_description" && creationSource != "meet_file" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid companion creation source"})
		return
	}
	avatarURL := ""
	if req.AvatarMediaID != nil && strings.TrimSpace(*req.AvatarMediaID) != "" {
		mediaID := strings.TrimSpace(*req.AvatarMediaID)
		var exists bool
		if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM media_assets WHERE id=$1 AND user_id=$2 AND kind='image')`, mediaID, userID).Scan(&exists); err != nil || !exists {
			c.JSON(http.StatusBadRequest, gin.H{"error": "character image is unavailable"})
			return
		}
		avatarURL = "/v1/media/" + mediaID
		req.AvatarMediaID = &mediaID
	}
	if creationSource != "tags_portrait" && avatarURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "AI-created companions require a character image"})
		return
	}
	tags, _ := json.Marshal(req.PersonalityTags)
	tx, err := db.Get().Begin()
	if err == nil {
		_, err = tx.Exec(`INSERT INTO companions
			(id,user_id,name,gender,persona,appearance,city,occupation,interests,relationship_stage,
			 personality_tags,speaking_style,likes,dislikes,life_habits,life_goal,backstory,portrait_id,avatar_url,creation_source,proactive_enabled,active)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,true,true)`,
			companionID, userID, req.Name, req.Gender, req.Persona, req.Appearance, req.City, req.Occupation, req.Interests,
			req.RelationshipStage, tags, req.SpeakingStyle, req.Likes, req.Dislikes, req.LifeHabits, req.LifeGoal, req.Backstory, req.PortraitID, avatarURL, creationSource)
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO relationship_states (companion_id) VALUES ($1)`, companionID)
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO companion_states (companion_id) VALUES ($1)`, companionID)
	}
	if err == nil {
		err = tx.Commit()
	} else if tx != nil {
		_ = tx.Rollback()
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create companion"})
		return
	}
	c.JSON(http.StatusCreated, Companion{
		ID: companionID, UserID: userID, Name: req.Name,
		Gender: req.Gender, Persona: req.Persona,
		RelationshipStage: req.RelationshipStage, PersonalityTags: req.PersonalityTags,
		SpeakingStyle: req.SpeakingStyle, Likes: req.Likes, Dislikes: req.Dislikes,
		LifeHabits: req.LifeHabits, LifeGoal: req.LifeGoal, Backstory: req.Backstory,
		PortraitID: req.PortraitID, PortraitURL: avatarURL, CreationSource: creationSource, ProactiveEnabled: true, Active: true,
		LifeEnabled: true, FriendshipActive: true, CanChat: true,
	})
}

func GetCompanion(c *gin.Context) {
	id := c.Param("id")
	var comp Companion
	var tags string
	var portraitID, modelID sql.NullString
	err := db.Get().QueryRow(`SELECT c.id,c.user_id,c.name,COALESCE(c.gender,''),COALESCE(c.persona,''),COALESCE(c.appearance,''),COALESCE(c.city,''),COALESCE(c.occupation,''),COALESCE(c.interests,''),COALESCE(c.relationship_stage,'stranger'),c.personality_tags::text,c.speaking_style,c.likes,c.dislikes,c.life_habits,c.life_goal,c.backstory,c.portrait_id,COALESCE(NULLIF(c.avatar_url,''),p.image_url,''),c.model_id,c.creation_source,c.proactive_enabled,c.active,c.is_default,c.life_enabled,c.friendship_active,c.created_at,c.updated_at FROM companions c LEFT JOIN companion_portraits p ON p.id=c.portrait_id WHERE c.id=$1 AND c.user_id=$2`, id, c.GetString("user_id")).Scan(
		&comp.ID, &comp.UserID, &comp.Name, &comp.Gender, &comp.Persona, &comp.Appearance, &comp.City, &comp.Occupation, &comp.Interests, &comp.RelationshipStage, &tags, &comp.SpeakingStyle, &comp.Likes, &comp.Dislikes, &comp.LifeHabits, &comp.LifeGoal, &comp.Backstory, &portraitID, &comp.PortraitURL, &modelID, &comp.CreationSource, &comp.ProactiveEnabled, &comp.Active, &comp.IsDefault, &comp.LifeEnabled, &comp.FriendshipActive, &comp.CreatedAt, &comp.UpdatedAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	_ = json.Unmarshal([]byte(tags), &comp.PersonalityTags)
	comp.PortraitID = nullString(portraitID)
	comp.ModelID = nullString(modelID)
	decorateCompanionAccess(c.GetString("user_id"), &comp)
	c.JSON(http.StatusOK, comp)
}

func ListCompanions(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := ensureDefaultCompanions(userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to prepare default companions"})
		return
	}
	rows, err := db.Get().Query(`SELECT c.id,c.user_id,c.name,COALESCE(c.gender,''),COALESCE(c.persona,''),COALESCE(c.appearance,''),COALESCE(c.city,''),COALESCE(c.occupation,''),COALESCE(c.interests,''),COALESCE(c.relationship_stage,'stranger'),c.personality_tags::text,c.speaking_style,c.likes,c.dislikes,c.life_habits,c.life_goal,c.backstory,c.portrait_id,COALESCE(NULLIF(c.avatar_url,''),p.image_url,''),c.model_id,c.creation_source,c.proactive_enabled,c.active,c.is_default,c.life_enabled,c.friendship_active,c.created_at,c.updated_at,
		COALESCE(latest.content,''),COALESCE(latest.message_type,'text'),latest.created_at,COALESCE(unread.count,0)
		FROM companions c
		LEFT JOIN companion_portraits p ON p.id=c.portrait_id
		LEFT JOIN LATERAL (
			SELECT m.content,m.message_type,m.created_at
			FROM conversations conversation JOIN messages m ON m.conversation_id=conversation.id
			WHERE conversation.user_id=$1 AND conversation.companion_id=c.id
			ORDER BY m.created_at DESC LIMIT 1
		) latest ON true
		LEFT JOIN LATERAL (
			SELECT COUNT(*) AS count
			FROM conversations conversation JOIN messages m ON m.conversation_id=conversation.id
			WHERE conversation.user_id=$1 AND conversation.companion_id=c.id
			  AND m.sender_type='assistant' AND m.created_at>COALESCE(conversation.last_read_at,conversation.created_at)
		) unread ON true
		WHERE c.user_id=$1 AND c.active=true
		ORDER BY latest.created_at DESC NULLS LAST,c.is_default DESC,c.created_at DESC`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list companions"})
		return
	}
	defer rows.Close()
	var companions []Companion
	for rows.Next() {
		var comp Companion
		var tags string
		var portraitID, modelID sql.NullString
		var lastMessageAt sql.NullTime
		if err := rows.Scan(&comp.ID, &comp.UserID, &comp.Name, &comp.Gender, &comp.Persona, &comp.Appearance, &comp.City, &comp.Occupation, &comp.Interests, &comp.RelationshipStage, &tags, &comp.SpeakingStyle, &comp.Likes, &comp.Dislikes, &comp.LifeHabits, &comp.LifeGoal, &comp.Backstory, &portraitID, &comp.PortraitURL, &modelID, &comp.CreationSource, &comp.ProactiveEnabled, &comp.Active, &comp.IsDefault, &comp.LifeEnabled, &comp.FriendshipActive, &comp.CreatedAt, &comp.UpdatedAt, &comp.LastMessage, &comp.LastMessageType, &lastMessageAt, &comp.UnreadCount); err != nil {
			continue
		}
		_ = json.Unmarshal([]byte(tags), &comp.PersonalityTags)
		comp.PortraitID = nullString(portraitID)
		comp.ModelID = nullString(modelID)
		comp.LastMessageAt = nullTime(lastMessageAt)
		decorateCompanionAccess(userID, &comp)
		companions = append(companions, comp)
	}
	c.JSON(http.StatusOK, companions)
}

func UpdateCompanion(c *gin.Context) {
	id := c.Param("id")
	var req CreateCompanionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if len(req.PersonalityTags) > 8 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "choose no more than 8 personality tags"})
		return
	}
	tags, _ := json.Marshal(req.PersonalityTags)
	result, err := db.Get().Exec(`UPDATE companions SET name=$3,gender=$4,persona=$5,appearance=$6,city=$7,occupation=$8,interests=$9,relationship_stage=$10,personality_tags=$11,speaking_style=$12,likes=$13,dislikes=$14,life_habits=$15,life_goal=$16,backstory=$17,portrait_id=$18,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2`, id, c.GetString("user_id"), req.Name, req.Gender, req.Persona, req.Appearance, req.City, req.Occupation, req.Interests, req.RelationshipStage, tags, req.SpeakingStyle, req.Likes, req.Dislikes, req.LifeHabits, req.LifeGoal, req.Backstory, req.PortraitID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to update companion"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	GetCompanion(c)
}

func DeleteCompanion(c *gin.Context) {
	userID := c.GetString("user_id")
	subscribed, err := userHasActiveSubscription(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check subscription"})
		return
	}
	purgeAfter := time.Now().UTC().Add(companionRecoveryWindow)
	result, err := db.Get().ExecContext(c.Request.Context(), `UPDATE companions SET
		active=false,friendship_active=false,life_enabled=$3,
		deleted_at=CURRENT_TIMESTAMP,purge_after=$4,updated_at=CURRENT_TIMESTAMP
		WHERE id=$1 AND user_id=$2 AND is_default=false AND deleted_at IS NULL`,
		c.Param("id"), userID, subscribed, purgeAfter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete companion"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "companion deleted", "purge_after": purgeAfter,
		"life_engine_running": subscribed,
	})
}

type SendMessageRequest struct {
	Content     string `json:"content"`
	MessageType string `json:"message_type"`
	MediaID     string `json:"media_id"`
}

type SendMessageResponse struct {
	ID               string              `json:"id"`
	Content          string              `json:"content"`
	Sender           string              `json:"sender"`
	Created          time.Time           `json:"created_at"`
	UserMessage      *agent.SavedMessage `json:"user_message,omitempty"`
	CompanionMessage *agent.SavedMessage `json:"companion_message"`
	AgentError       string              `json:"agent_error,omitempty"`
}

func SendMessage(c *gin.Context) {
	conversationID := c.Param("id")
	var req SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	msgID := uuid.New().String()
	userID := c.GetString("user_id")
	if req.MessageType == "" {
		req.MessageType = "text"
	}
	if req.MessageType != "text" && req.MessageType != "voice" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported message type"})
		return
	}
	if req.MessageType == "text" && strings.TrimSpace(req.Content) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message content is required"})
		return
	}
	if req.MessageType == "voice" && strings.TrimSpace(req.MediaID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "voice media is required"})
		return
	}
	var companionID string
	var isDefault bool
	if err := db.Get().QueryRow(`SELECT cp.id,cp.is_default FROM conversations cv JOIN companions cp ON cp.id=cv.companion_id WHERE cv.id=$1 AND cv.user_id=$2 AND cp.active=true`, conversationID, userID).Scan(&companionID, &isDefault); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}
	if isDefault {
		allowed, expires, err := defaultChatAccess(userID, true)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check free chat access"})
			return
		}
		if !allowed {
			subscriptionRequired(c, "default_chat_trial_expired", "The free default-companion chat period has ended. Subscribe to continue")
			return
		}
		_ = expires
	} else {
		subscribed, err := userHasActiveSubscription(userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check subscription"})
			return
		}
		if !subscribed {
			_ = syncUserCompanionEntitlement(userID, false)
			subscriptionRequired(c, "friendship_inactive", "You are no longer friends, so messages cannot be sent. Subscribe to reconnect")
			return
		}
	}
	createdAt := time.Now().UTC()
	appLocale := language.Normalize(c.GetHeader("Accept-Language"))
	_, _ = db.Get().Exec(`UPDATE users SET preferred_locale=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2`, appLocale, userID)
	mediaURL := ""
	if req.MessageType == "voice" {
		if companionAgent == nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "agent service is unavailable"})
			return
		}
		transcript, transcriptErr := companionAgent.TranscribeMedia(c.Request.Context(), strings.TrimSpace(req.MediaID), userID, companionID)
		if transcriptErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "voice message could not be transcribed"})
			return
		}
		req.Content = transcript
		mediaURL = "/v1/media/" + strings.TrimSpace(req.MediaID)
	}
	query := `INSERT INTO messages (id,conversation_id,sender_type,message_type,content,media_url,payload,source,delivery_status,created_at) VALUES ($1,$2,'user',$3,$4,NULLIF($5,''),'{}'::jsonb,'user','delivered',$6)`
	_, err := db.Get().Exec(query, msgID, conversationID, req.MessageType, req.Content, mediaURL, createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}
	userMessage := &agent.SavedMessage{ID: msgID, ConversationID: conversationID, SenderType: "user", MessageType: req.MessageType, Content: req.Content, MediaURL: mediaURL, Payload: map[string]any{}, Source: "user", DeliveryStatus: "delivered", CreatedAt: createdAt}
	response := SendMessageResponse{ID: msgID, Content: req.Content, Sender: "user", Created: createdAt, UserMessage: userMessage}
	if companionAgent == nil {
		response.AgentError = "agent service is unavailable"
		c.JSON(http.StatusCreated, response)
		return
	}
	replyCtx, cancel := context.WithTimeout(c.Request.Context(), 50*time.Second)
	defer cancel()
	reply, replyErr := companionAgent.Reply(replyCtx, conversationID, userID)
	if replyErr != nil {
		response.AgentError = "companion could not reply yet"
	} else {
		response.CompanionMessage = reply
	}
	c.JSON(http.StatusCreated, response)
}

func GetMessages(c *gin.Context) {
	conversationID := c.Param("id")
	userID := c.GetString("user_id")
	query := `SELECT m.id,m.conversation_id,m.sender_type,m.message_type,COALESCE(m.content,''),COALESCE(m.media_url,''),m.payload::text,m.source,COALESCE(m.life_event_id,''),m.delivery_status,m.created_at FROM messages m JOIN conversations c ON c.id=m.conversation_id WHERE m.conversation_id=$1 AND c.user_id=$2`
	args := []any{conversationID, userID}
	if after := c.Query("after"); after != "" {
		if parsed, parseErr := time.Parse(time.RFC3339Nano, after); parseErr == nil {
			query += ` AND m.created_at > $3`
			args = append(args, parsed)
		}
	}
	query += ` ORDER BY m.created_at ASC`
	rows, err := db.Get().Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get messages"})
		return
	}
	defer rows.Close()
	var messages []map[string]interface{}
	for rows.Next() {
		var m map[string]interface{}
		var id, conversationID, senderType, messageType, content, mediaURL, payloadRaw, source, lifeEventID, deliveryStatus string
		var created time.Time
		if err := rows.Scan(&id, &conversationID, &senderType, &messageType, &content, &mediaURL, &payloadRaw, &source, &lifeEventID, &deliveryStatus, &created); err != nil {
			continue
		}
		payload := map[string]any{}
		_ = json.Unmarshal([]byte(payloadRaw), &payload)
		m = map[string]interface{}{"id": id, "conversation_id": conversationID, "sender_type": senderType, "message_type": messageType, "content": content, "media_url": mediaURL, "payload": payload, "source": source, "life_event_id": lifeEventID, "delivery_status": deliveryStatus, "created_at": created}
		messages = append(messages, m)
	}
	_, _ = db.Get().Exec(`UPDATE conversations SET last_read_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2`, conversationID, userID)
	c.JSON(http.StatusOK, messages)
}

// GetConversationMedia returns the complete image and voice history for one
// owned conversation. It is paginated independently from the chat timeline so
// the App does not need to load every text message to build the media gallery.
func GetConversationMedia(c *gin.Context) {
	conversationID := c.Param("id")
	userID := c.GetString("user_id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "30"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 30
	}
	if pageSize > 100 {
		pageSize = 100
	}
	var exists bool
	if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM conversations WHERE id=$1 AND user_id=$2)`, conversationID, userID).Scan(&exists); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify conversation"})
		return
	}
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}
	var total int
	if err := db.Get().QueryRow(`SELECT COUNT(*) FROM messages
		WHERE conversation_id=$1 AND COALESCE(media_url,'')<>''
		AND (message_type='voice' OR message_type IN ('image','image_text') OR COALESCE(payload->>'media_kind','')='image')`, conversationID).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to count conversation media"})
		return
	}
	rows, err := db.Get().Query(`SELECT id,sender_type,message_type,COALESCE(content,''),COALESCE(media_url,''),payload::text,created_at
		FROM messages WHERE conversation_id=$1 AND COALESCE(media_url,'')<>''
		AND (message_type='voice' OR message_type IN ('image','image_text') OR COALESCE(payload->>'media_kind','')='image')
		ORDER BY created_at DESC,id DESC LIMIT $2 OFFSET $3`, conversationID, pageSize, (page-1)*pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get conversation media"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, senderType, messageType, content, mediaURL, payloadRaw string
		var createdAt time.Time
		if err := rows.Scan(&id, &senderType, &messageType, &content, &mediaURL, &payloadRaw, &createdAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read conversation media"})
			return
		}
		payload := map[string]any{}
		_ = json.Unmarshal([]byte(payloadRaw), &payload)
		kind := "image"
		if messageType == "voice" {
			kind = "voice"
		}
		items = append(items, gin.H{"id": id, "sender_type": senderType, "message_type": messageType,
			"kind": kind, "content": content, "media_url": mediaURL, "payload": payload, "created_at": createdAt})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read conversation media"})
		return
	}
	totalPages := 0
	if total > 0 {
		totalPages = (total + pageSize - 1) / pageSize
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "total": total, "page": page, "page_size": pageSize, "total_pages": totalPages})
}

// GetOrCreateConversation returns the conversation between the current user and
// a companion, creating it on first use (required by the mobile chat flow).
func GetOrCreateConversation(c *gin.Context) {
	userID := c.GetString("user_id")
	var req struct {
		CompanionID string `json:"companion_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var ownerID string
	var isDefault bool
	if err := db.Get().QueryRow(
		`SELECT user_id,is_default FROM companions WHERE id = $1 AND active=true`, req.CompanionID).Scan(&ownerID, &isDefault); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	if ownerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "companion does not belong to user"})
		return
	}
	canSend := true
	accessCode := ""
	if isDefault {
		allowed, expires, err := defaultChatAccess(userID, true)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start free chat access"})
			return
		}
		if !allowed {
			canSend = false
			accessCode = "default_chat_trial_expired"
		}
		if expires != nil {
			c.Header("X-Vita-Trial-Expires-At", expires.Format(time.RFC3339))
		}
	}
	if !isDefault {
		active, accessErr := userHasActiveSubscription(userID)
		if accessErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check subscription"})
			return
		}
		if !active {
			canSend = false
			accessCode = "friendship_inactive"
			_ = syncUserCompanionEntitlement(userID, false)
		}
	}

	var conversationID string
	err := db.Get().QueryRow(
		`SELECT id FROM conversations WHERE user_id = $1 AND companion_id = $2 LIMIT 1`,
		userID, req.CompanionID).Scan(&conversationID)
	if err == nil {
		response := gin.H{"conversation_id": conversationID, "can_send": canSend, "access_code": accessCode}
		if companionAgent != nil {
			if status, statusErr := companionAgent.CurrentStatus(c.Request.Context(), req.CompanionID, userID); statusErr == nil {
				response["companion_status"] = status
			}
		}
		c.JSON(http.StatusOK, response)
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load conversation"})
		return
	}

	conversationID = uuid.New().String()
	if _, err := db.Get().Exec(
		`INSERT INTO conversations (id, user_id, companion_id) VALUES ($1, $2, $3)`,
		conversationID, userID, req.CompanionID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create conversation"})
		return
	}
	response := gin.H{"conversation_id": conversationID, "can_send": canSend, "access_code": accessCode}
	if companionAgent != nil {
		if status, statusErr := companionAgent.CurrentStatus(c.Request.Context(), req.CompanionID, userID); statusErr == nil {
			response["companion_status"] = status
		}
	}
	c.JSON(http.StatusCreated, response)
}

func GetTodayLife(c *gin.Context) {
	companionID := c.Param("id")
	if !requireCompanionLifeAccess(c, companionID) {
		return
	}
	var timezone string
	if err := db.Get().QueryRow(`SELECT COALESCE(u.timezone,'UTC') FROM companions c JOIN users u ON u.id=c.user_id WHERE c.id=$1 AND c.user_id=$2`, companionID, c.GetString("user_id")).Scan(&timezone); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	location, err := time.LoadLocation(timezone)
	if err != nil {
		location = time.UTC
	}
	localDate := time.Now().In(location).Format("2006-01-02")
	rows, err := db.Get().Query(`SELECT e.id,COALESCE(e.event_type,''),COALESCE(e.title,''),COALESCE(e.description,''),COALESCE(e.location,''),e.start_time,e.end_time,COALESCE(e.emotion,''),e.importance,e.user_relevance,e.shareability,e.payload::text,e.generation_source,e.shared_at FROM life_events e JOIN companions c ON c.id=e.companion_id WHERE e.companion_id=$1 AND c.user_id=$2 AND e.local_date=$3 ORDER BY e.start_time`, companionID, c.GetString("user_id"), localDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get today's life"})
		return
	}
	defer rows.Close()
	var events []map[string]interface{}
	for rows.Next() {
		var id, eventType, title, description, location string
		var startTime, endTime time.Time
		var emotion, payloadRaw, generationSource string
		var importance, userRelevance int
		var shareability bool
		var sharedAt sql.NullTime
		if err := rows.Scan(&id, &eventType, &title, &description, &location, &startTime, &endTime, &emotion, &importance, &userRelevance, &shareability, &payloadRaw, &generationSource, &sharedAt); err != nil {
			continue
		}
		payload := map[string]any{}
		_ = json.Unmarshal([]byte(payloadRaw), &payload)
		m := map[string]interface{}{
			"id": id, "event_type": eventType, "title": title,
			"description": description, "location": location,
			"start_time": startTime, "end_time": endTime,
			"emotion": emotion, "importance": importance, "user_relevance": userRelevance,
			"shareability": shareability, "payload": payload, "generation_source": generationSource, "shared_at": nullTime(sharedAt),
		}
		events = append(events, m)
	}
	c.JSON(http.StatusOK, events)
}

func GetLifeEvents(c *gin.Context) {
	companionID := c.Param("id")
	if !requireCompanionLifeAccess(c, companionID) {
		return
	}
	rows, err := db.Get().Query(`SELECT e.id,COALESCE(e.event_type,''),COALESCE(e.title,''),COALESCE(e.description,''),COALESCE(e.location,''),e.start_time,e.end_time,COALESCE(e.emotion,''),e.importance,e.user_relevance,e.shareability,e.payload::text,e.generation_source,e.shared_at FROM life_events e JOIN companions c ON c.id=e.companion_id WHERE e.companion_id=$1 AND c.user_id=$2 ORDER BY e.start_time DESC LIMIT 200`, companionID, c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get life events"})
		return
	}
	defer rows.Close()
	events := make([]gin.H, 0)
	for rows.Next() {
		var id, eventType, title, description, location, emotion, payloadRaw, generationSource string
		var startTime, endTime time.Time
		var importance, userRelevance int
		var shareability bool
		var sharedAt sql.NullTime
		if rows.Scan(&id, &eventType, &title, &description, &location, &startTime, &endTime, &emotion, &importance, &userRelevance, &shareability, &payloadRaw, &generationSource, &sharedAt) != nil {
			continue
		}
		payload := map[string]any{}
		_ = json.Unmarshal([]byte(payloadRaw), &payload)
		events = append(events, gin.H{"id": id, "event_type": eventType, "title": title, "description": description, "location": location, "start_time": startTime, "end_time": endTime, "emotion": emotion, "importance": importance, "user_relevance": userRelevance, "shareability": shareability, "payload": payload, "generation_source": generationSource, "shared_at": nullTime(sharedAt)})
	}
	c.JSON(http.StatusOK, gin.H{"events": events})
}

func GetMemories(c *gin.Context) {
	rows, err := db.Get().Query(`SELECT m.id,COALESCE(m.type,''),COALESCE(m.content,''),m.importance,m.event_time,COALESCE(m.metadata,''),m.created_at FROM memories m JOIN companions c ON c.id=m.companion_id WHERE m.companion_id=$1 AND c.user_id=$2 ORDER BY m.importance DESC,m.created_at DESC`, c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get memories"})
		return
	}
	defer rows.Close()
	memories := make([]gin.H, 0)
	for rows.Next() {
		var id, kind, content, metadata string
		var importance int
		var eventTime sql.NullTime
		var created time.Time
		if rows.Scan(&id, &kind, &content, &importance, &eventTime, &metadata, &created) != nil {
			continue
		}
		memories = append(memories, gin.H{"id": id, "type": kind, "content": content, "importance": importance, "event_time": nullTime(eventTime), "metadata": metadata, "created_at": created})
	}
	keepsakeRows, keepsakeErr := db.Get().Query(`SELECT k.id,k.title,k.content,k.payload::text,k.created_at
		FROM companion_keepsakes k JOIN companions c ON c.id=k.companion_id
		WHERE k.companion_id=$1 AND c.user_id=$2 ORDER BY k.created_at DESC`, c.Param("id"), c.GetString("user_id"))
	if keepsakeErr == nil {
		defer keepsakeRows.Close()
		for keepsakeRows.Next() {
			var id, title, content, payload string
			var created time.Time
			if keepsakeRows.Scan(&id, &title, &content, &payload, &created) == nil {
				memories = append([]gin.H{{"id": id, "type": "keepsake", "title": title, "content": content, "importance": 100, "event_time": created, "metadata": payload, "created_at": created, "readonly": true}}, memories...)
			}
		}
	}
	c.JSON(http.StatusOK, gin.H{"memories": memories})
}

func UpdateMemory(c *gin.Context) {
	var input struct {
		Content string `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Content = strings.TrimSpace(input.Content)
	if input.Content == "" || len([]rune(input.Content)) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "memory content must contain 1 to 500 characters"})
		return
	}
	metadata, _ := json.Marshal(map[string]any{"source": "user_correction", "confirmed": true})
	result, err := db.Get().Exec(`UPDATE memories m SET content=$1,metadata=$2
		FROM companions c WHERE m.id=$3 AND m.companion_id=$4 AND c.id=m.companion_id AND c.user_id=$5`,
		input.Content, metadata, c.Param("memory_id"), c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update memory"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "memory not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": c.Param("memory_id"), "content": input.Content})
}

func DeleteMemory(c *gin.Context) {
	result, err := db.Get().Exec(`DELETE FROM memories m USING companions c
		WHERE m.id=$1 AND m.companion_id=$2 AND c.id=m.companion_id AND c.user_id=$3`,
		c.Param("memory_id"), c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete memory"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "memory not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "memory deleted"})
}

// GetExplorePosts returns posts from the user's own companions and characters
// they have met. The query intentionally exposes character-facing fields only;
// no owner identity, chat content or private memory crosses user boundaries.
func GetExplorePosts(c *gin.Context) {
	rows, err := db.Get().Query(`
		WITH owned AS (
			SELECT c.id FROM companions c WHERE c.user_id=$1 AND c.active=true AND c.life_enabled=true
			  AND EXISTS(SELECT 1 FROM subscriptions s WHERE s.user_id=c.user_id AND s.status='active'
			    AND (s.current_period_end IS NULL OR s.current_period_end>CURRENT_TIMESTAMP))
		), visible AS (
			SELECT id FROM owned
			UNION
			SELECT CASE WHEN r.companion_a_id=o.id THEN r.companion_b_id ELSE r.companion_a_id END
			FROM companion_relationships r JOIN owned o ON o.id IN (r.companion_a_id,r.companion_b_id)
			WHERE r.status='active'
		)
		SELECT p.id,p.post_type,p.content,p.media_urls::text,p.payload::text,p.published_at,
		       author.id,author.name,COALESCE(NULLIF(author.avatar_url,''),ap.image_url,''),
		       related.id,related.name,COALESCE(NULLIF(related.avatar_url,''),rp.image_url,''),
		       (author.user_id=$1)
		FROM moment_posts p
		JOIN visible v ON v.id=p.author_companion_id
		JOIN companions author ON author.id=p.author_companion_id AND author.active=true
		LEFT JOIN companion_portraits ap ON ap.id=author.portrait_id
		LEFT JOIN life_events le ON le.id=p.life_event_id
		LEFT JOIN companions related ON related.id=le.related_companion_id
		LEFT JOIN companion_portraits rp ON rp.id=related.portrait_id
		ORDER BY p.published_at DESC LIMIT 100`, c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load explore posts"})
		return
	}
	defer rows.Close()
	posts := make([]gin.H, 0)
	for rows.Next() {
		var id, postType, content, mediaRaw, payloadRaw string
		var published time.Time
		var authorID, authorName, authorPortrait string
		var relatedID, relatedName, relatedPortrait sql.NullString
		var own bool
		if err := rows.Scan(&id, &postType, &content, &mediaRaw, &payloadRaw, &published, &authorID, &authorName, &authorPortrait, &relatedID, &relatedName, &relatedPortrait, &own); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read explore posts"})
			return
		}
		media := make([]string, 0)
		payload := map[string]any{}
		_ = json.Unmarshal([]byte(mediaRaw), &media)
		_ = json.Unmarshal([]byte(payloadRaw), &payload)
		var related any
		if relatedID.Valid {
			related = gin.H{"id": relatedID.String, "name": relatedName.String, "portrait_url": relatedPortrait.String}
		}
		posts = append(posts, gin.H{
			"id": id, "post_type": postType, "content": content, "media_urls": media,
			"payload": payload, "published_at": published, "is_own_companion": own,
			"author":            gin.H{"id": authorID, "name": authorName, "portrait_url": authorPortrait},
			"related_companion": related,
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load explore posts"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

func UploadMedia(c *gin.Context) {
	if mediaStorage == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "media storage is unavailable"})
		return
	}
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "media file is required"})
		return
	}
	defer file.Close()
	kind := strings.ToLower(strings.TrimSpace(c.PostForm("kind")))
	if kind != "audio" && kind != "image" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "media kind must be audio or image"})
		return
	}
	const maxUpload = 10 << 20
	data, err := io.ReadAll(io.LimitReader(file, maxUpload+1))
	if err != nil || len(data) == 0 || len(data) > maxUpload {
		c.JSON(http.StatusBadRequest, gin.H{"error": "media must contain 1 byte to 10 MB"})
		return
	}
	mimeType := header.Header.Get("Content-Type")
	if mimeType == "" {
		mimeType = http.DetectContentType(data)
	}
	if (kind == "audio" && !strings.HasPrefix(mimeType, "audio/")) || (kind == "image" && !strings.HasPrefix(mimeType, "image/")) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "media content type does not match kind"})
		return
	}
	id := uuid.New().String()
	if err := mediaStorage.Store(c.Request.Context(), c.GetString("user_id"), id, kind, mimeType, data); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to store media"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": id, "url": "/v1/media/" + id, "mime_type": mimeType, "size_bytes": len(data)})
}

func GetMedia(c *gin.Context) {
	if mediaStorage == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "media storage is unavailable"})
		return
	}
	media, err := mediaStorage.Open(c.Request.Context(), c.Param("id"), c.GetString("user_id"))
	if errors.Is(err, storage.ErrNotFound) {
		c.Status(http.StatusNotFound)
		return
	}
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to load media"})
		return
	}
	defer media.Body.Close()
	c.Header("Cache-Control", "private, max-age=86400")
	c.DataFromReader(http.StatusOK, media.Size, media.MimeType, media.Body, nil)
}

func GenerateMedia(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"job_id": uuid.New().String(), "status": "queued"})
}

// --- Token Generation ---

type TokenResponse struct {
	Token        string `json:"token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

func issueTokens(userID, role string) (TokenResponse, error) {
	if tokenManager == nil {
		return TokenResponse{}, errors.New("token manager is not initialized")
	}
	pair, err := tokenManager.Issue(userID, role)
	if err != nil {
		return TokenResponse{}, err
	}
	return TokenResponse{
		Token:        pair.AccessToken,
		RefreshToken: pair.RefreshToken,
		ExpiresIn:    pair.ExpiresIn,
	}, nil
}

package handler

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"vita/internal/agent"
	"vita/internal/auth"
	"vita/internal/config"
	"vita/internal/db"
	"vita/internal/mail"
)

const jwtSecret = "dev-secret-change-me-32-characters-min"
const codeLength = 6
const codeTTL = 5 * time.Minute

var rdb *redis.Client

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

func InitRedis(redisURL string) {
	var err error
	rdb = redis.NewClient(&redis.Options{
		Addr:     redisURL,
		Password: "",
		DB:       0,
	})
	if err != nil {
		fmt.Printf("Warning: Redis connection failed: %v\n", err)
	}
}

type HealthResponse struct {
	Status  string `json:"status"`
	Version string `json:"version"`
}

func Health(c *gin.Context) {
	c.JSON(http.StatusOK, HealthResponse{Status: "ok", Version: "0.1.0"})
}

// --- Verification Code ---

type SendCodeRequest struct {
	Email   string `json:"email" binding:"required,email"`
	Purpose string `json:"purpose"`
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
	if err != nil {
		// User doesn't exist, auto-register as user
		userID = uuid.New().String()
		_, err = db.Get().Exec(`INSERT INTO users (id, email, role_id, environment) VALUES ($1, $2, 'user', $3)`, userID, req.Email, currentEnvironment())
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
			return
		}
		userRole = "user"
	}

	// Generate verification code
	code := generateCode()
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
	err = rdb.Set(ctx, "vcode:"+code, string(codeJSON), codeTTL).Err()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store verification code"})
		return
	}

	// Also store in DB for backup
	codeID := uuid.New().String()
	_, err = db.Get().Exec(`INSERT INTO verification_codes (id, email, code, purpose, expires_at) VALUES ($1, $2, $3, $4, $4)`,
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

func generateCode() string {
	bytes := make([]byte, 3)
	rand.Read(bytes)
	return fmt.Sprintf("%06d", int32(bytes[0])<<16|int32(bytes[1])<<8|int32(bytes[2]))
}

// --- Auth Routes ---

type RegisterRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type RegisterResponse struct {
	UserID string `json:"user_id"`
	Token  string `json:"token"`
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

	token, err := generateToken(uuid.MustParse(userID), "user")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}
	c.JSON(http.StatusCreated, RegisterResponse{UserID: userID, Token: token})
}

type LoginRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code" binding:"required,len=6"`
}

type LoginResponse struct {
	UserID string `json:"user_id"`
	Token  string `json:"token"`
	Role   string `json:"role"`
}

func Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify code from Redis
	ctx := context.Background()
	codeDataJSON, err := rdb.Get(ctx, "vcode:"+req.Code).Result()
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
	if codeData["email"] != req.Email {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "verification code does not match this email"})
		return
	}

	// Mark code as used (delete from Redis)
	rdb.Del(ctx, "vcode:"+req.Code)

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

	token, err := generateToken(func() uuid.UUID { u, _ := uuid.Parse(userID); return u }(), userRole)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, LoginResponse{UserID: userID, Token: token, Role: userRole})
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
	Token  string `json:"token"`
	Role   string `json:"role"`
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

	token, err := generateToken(parseUUID(userID), "admin")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, AdminLoginResponse{UserID: userID, Token: token, Role: "admin"})
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
	codeDataJSON, err := rdb.Get(ctx, "vcode:"+code).Result()
	if err != nil {
		return "", errors.New("invalid or expired verification code")
	}

	var codeData map[string]string
	if err := json.Unmarshal([]byte(codeDataJSON), &codeData); err != nil {
		return "", errors.New("invalid verification code")
	}

	if codeData["email"] != email {
		return "", errors.New("verification code does not match this email")
	}

	rdb.Del(ctx, "vcode:"+code)
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
	UserID    string    `json:"user_id"`
	Email     string    `json:"email"`
	Role      string    `json:"role"`
	Timezone  string    `json:"timezone"`
	CreatedAt time.Time `json:"created_at"`
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
		`SELECT id, email, COALESCE(role_id, 'user'), COALESCE(timezone, 'UTC'), created_at FROM users WHERE id = $1`,
		userID).Scan(&p.UserID, &p.Email, &p.Role, &p.Timezone, &p.CreatedAt)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "account not found"})
		return
	}

	c.JSON(http.StatusOK, p)
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
	Token  string `json:"token"`
	Role   string `json:"role"`
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

	token, err := generateToken(uuid.MustParse(userID), role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, AppLoginResponse{UserID: userID, Token: token, Role: role})
}

// --- App Registration (email + password + verification code) ---

const registerCooldown = 60 * time.Second

const pendingRegPrefix = "vita:reg:"

type AppRegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
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

	ctx := context.Background()
	cooldownKey := "vcode:cooldown:" + req.Email
	if rdb.Exists(ctx, cooldownKey).Val() > 0 {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "please wait 60 seconds before requesting another code"})
		return
	}

	var exists bool
	err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)`, req.Email).Scan(&exists)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check email"})
		return
	}
	if exists {
		c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
		return
	}

	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register"})
		return
	}

	// Remember the password until the code is verified (same window as the code).
	pendingKey := pendingRegPrefix + req.Email
	if err := rdb.Set(ctx, pendingKey, hash, codeTTL).Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start registration"})
		return
	}

	code := generateCode()
	codeJSON, _ := json.Marshal(map[string]string{
		"email":   req.Email,
		"purpose": "register",
	})
	if err := rdb.Set(ctx, "vcode:"+code, string(codeJSON), codeTTL).Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send verification code"})
		return
	}
	rdb.Set(ctx, cooldownKey, "1", registerCooldown)

	if err := mailCfg.SendVerificationCode(req.Email, code); err != nil {
		// Roll back so the user can retry immediately.
		rdb.Del(ctx, pendingKey, "vcode:"+code, cooldownKey)
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
	codeDataJSON, err := rdb.Get(ctx, "vcode:"+req.Code).Result()
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired verification code"})
		return
	}
	var codeData map[string]string
	if err := json.Unmarshal([]byte(codeDataJSON), &codeData); err != nil ||
		codeData["email"] != req.Email || codeData["purpose"] != "register" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid verification code"})
		return
	}

	pendingKey := pendingRegPrefix + req.Email
	hash, err := rdb.Get(ctx, pendingKey).Result()
	if err != nil || hash == "" {
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
	if _, err := db.Get().Exec(
		`INSERT INTO users (id, email, role_id, password_hash, environment) VALUES ($1, $2, 'user', $3, $4)`,
		userID, req.Email, hash, currentEnvironment()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	// Consume the code and the pending registration.
	rdb.Del(ctx, "vcode:"+req.Code, pendingKey, "vcode:cooldown:"+req.Email)
	_, _ = db.Get().Exec(
		`INSERT INTO verification_codes (id, email, code, purpose, expires_at, used) VALUES ($1, $2, $3, 'register', $4, true)`,
		uuid.New().String(), req.Email, req.Code, time.Now().Add(codeTTL))

	token, err := generateToken(uuid.MustParse(userID), "user")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, AppLoginResponse{UserID: userID, Token: token, Role: "user"})
}

// WebappLogin - login endpoint for web app
type WebappLoginRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code" binding:"required,len=6"`
}

type WebappLoginResponse struct {
	UserID string `json:"user_id"`
	Token  string `json:"token"`
	Role   string `json:"role"`
}

func WebappLogin(c *gin.Context) {
	var req WebappLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := context.Background()
	codeDataJSON, err := rdb.Get(ctx, "vcode:"+req.Code).Result()
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired verification code"})
		return
	}

	var codeData map[string]string
	if err := json.Unmarshal([]byte(codeDataJSON), &codeData); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid verification code"})
		return
	}

	if codeData["email"] != req.Email {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "verification code does not match this email"})
		return
	}

	rdb.Del(ctx, "vcode:"+req.Code)
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

	token, err := generateToken(func() uuid.UUID { u, _ := uuid.Parse(userID); return u }(), role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, WebappLoginResponse{UserID: userID, Token: token, Role: role})
}

type LogoutResponse struct {
	Message string `json:"message"`
}

func Logout(c *gin.Context) {
	c.JSON(http.StatusOK, LogoutResponse{Message: "logged out"})
}

func RefreshToken(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"token": "new_token_placeholder"})
}

// --- Companion Routes ---

type Companion struct {
	ID                string    `json:"id"`
	UserID            string    `json:"user_id"`
	Name              string    `json:"name"`
	Gender            string    `json:"gender"`
	Persona           string    `json:"persona"`
	Appearance        string    `json:"appearance"`
	City              string    `json:"city"`
	Occupation        string    `json:"occupation"`
	Interests         string    `json:"interests"`
	RelationshipStage string    `json:"relationship_stage"`
	PersonalityTags   []string  `json:"personality_tags"`
	SpeakingStyle     string    `json:"speaking_style"`
	Likes             string    `json:"likes"`
	Dislikes          string    `json:"dislikes"`
	LifeHabits        string    `json:"life_habits"`
	LifeGoal          string    `json:"life_goal"`
	Backstory         string    `json:"backstory"`
	PortraitID        *string   `json:"portrait_id"`
	PortraitURL       string    `json:"portrait_url"`
	ModelID           *string   `json:"model_id"`
	CreationSource    string    `json:"creation_source"`
	ProactiveEnabled  bool      `json:"proactive_enabled"`
	Active            bool      `json:"active"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
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
}

func CreateCompanion(c *gin.Context) {
	var req CreateCompanionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	companionID := uuid.New().String()
	userID := c.GetString("user_id")
	if len(req.PersonalityTags) > 8 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "choose no more than 8 personality tags"})
		return
	}
	if req.RelationshipStage == "" {
		req.RelationshipStage = "stranger"
	}
	tags, _ := json.Marshal(req.PersonalityTags)
	tx, err := db.Get().Begin()
	if err == nil {
		_, err = tx.Exec(`INSERT INTO companions
			(id,user_id,name,gender,persona,appearance,city,occupation,interests,relationship_stage,
			 personality_tags,speaking_style,likes,dislikes,life_habits,life_goal,backstory,portrait_id,creation_source,proactive_enabled,active)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,'tags_portrait',true,true)`,
			companionID, userID, req.Name, req.Gender, req.Persona, req.Appearance, req.City, req.Occupation, req.Interests,
			req.RelationshipStage, tags, req.SpeakingStyle, req.Likes, req.Dislikes, req.LifeHabits, req.LifeGoal, req.Backstory, req.PortraitID)
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
		PortraitID: req.PortraitID, CreationSource: "tags_portrait", ProactiveEnabled: true, Active: true,
	})
}

func GetCompanion(c *gin.Context) {
	id := c.Param("id")
	var comp Companion
	var tags string
	var portraitID, modelID sql.NullString
	err := db.Get().QueryRow(`SELECT c.id,c.user_id,c.name,COALESCE(c.gender,''),COALESCE(c.persona,''),COALESCE(c.appearance,''),COALESCE(c.city,''),COALESCE(c.occupation,''),COALESCE(c.interests,''),COALESCE(c.relationship_stage,'stranger'),c.personality_tags::text,c.speaking_style,c.likes,c.dislikes,c.life_habits,c.life_goal,c.backstory,c.portrait_id,COALESCE(p.image_url,''),c.model_id,c.creation_source,c.proactive_enabled,c.active,c.created_at,c.updated_at FROM companions c LEFT JOIN companion_portraits p ON p.id=c.portrait_id WHERE c.id=$1 AND c.user_id=$2`, id, c.GetString("user_id")).Scan(
		&comp.ID, &comp.UserID, &comp.Name, &comp.Gender, &comp.Persona, &comp.Appearance, &comp.City, &comp.Occupation, &comp.Interests, &comp.RelationshipStage, &tags, &comp.SpeakingStyle, &comp.Likes, &comp.Dislikes, &comp.LifeHabits, &comp.LifeGoal, &comp.Backstory, &portraitID, &comp.PortraitURL, &modelID, &comp.CreationSource, &comp.ProactiveEnabled, &comp.Active, &comp.CreatedAt, &comp.UpdatedAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	_ = json.Unmarshal([]byte(tags), &comp.PersonalityTags)
	comp.PortraitID = nullString(portraitID)
	comp.ModelID = nullString(modelID)
	c.JSON(http.StatusOK, comp)
}

func ListCompanions(c *gin.Context) {
	rows, err := db.Get().Query(`SELECT c.id,c.user_id,c.name,COALESCE(c.gender,''),COALESCE(c.persona,''),COALESCE(c.appearance,''),COALESCE(c.city,''),COALESCE(c.occupation,''),COALESCE(c.interests,''),COALESCE(c.relationship_stage,'stranger'),c.personality_tags::text,c.speaking_style,c.likes,c.dislikes,c.life_habits,c.life_goal,c.backstory,c.portrait_id,COALESCE(p.image_url,''),c.model_id,c.creation_source,c.proactive_enabled,c.active,c.created_at,c.updated_at FROM companions c LEFT JOIN companion_portraits p ON p.id=c.portrait_id WHERE c.user_id=$1 AND c.active=true ORDER BY c.created_at DESC`, c.GetString("user_id"))
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
		if err := rows.Scan(&comp.ID, &comp.UserID, &comp.Name, &comp.Gender, &comp.Persona, &comp.Appearance, &comp.City, &comp.Occupation, &comp.Interests, &comp.RelationshipStage, &tags, &comp.SpeakingStyle, &comp.Likes, &comp.Dislikes, &comp.LifeHabits, &comp.LifeGoal, &comp.Backstory, &portraitID, &comp.PortraitURL, &modelID, &comp.CreationSource, &comp.ProactiveEnabled, &comp.Active, &comp.CreatedAt, &comp.UpdatedAt); err != nil {
			continue
		}
		_ = json.Unmarshal([]byte(tags), &comp.PersonalityTags)
		comp.PortraitID = nullString(portraitID)
		comp.ModelID = nullString(modelID)
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
	result, err := db.Get().Exec(`UPDATE companions SET active=false,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2`, c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete companion"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "companion deleted"})
}

type SendMessageRequest struct {
	Content     string `json:"content" binding:"required"`
	MessageType string `json:"message_type"`
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
	if req.MessageType != "text" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "this version supports text messages only"})
		return
	}
	var owns bool
	if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM conversations WHERE id=$1 AND user_id=$2)`, conversationID, userID).Scan(&owns); err != nil || !owns {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}
	createdAt := time.Now().UTC()
	query := `INSERT INTO messages (id,conversation_id,sender_type,message_type,content,payload,source,delivery_status,created_at) VALUES ($1,$2,'user',$3,$4,'{}'::jsonb,'user','delivered',$5)`
	_, err := db.Get().Exec(query, msgID, conversationID, req.MessageType, req.Content, createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}
	userMessage := &agent.SavedMessage{ID: msgID, ConversationID: conversationID, SenderType: "user", MessageType: req.MessageType, Content: req.Content, Payload: map[string]any{}, Source: "user", DeliveryStatus: "delivered", CreatedAt: createdAt}
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
	c.JSON(http.StatusOK, messages)
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
	if err := db.Get().QueryRow(
		`SELECT user_id FROM companions WHERE id = $1`, req.CompanionID).Scan(&ownerID); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	if ownerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "companion does not belong to user"})
		return
	}

	var conversationID string
	err := db.Get().QueryRow(
		`SELECT id FROM conversations WHERE user_id = $1 AND companion_id = $2 LIMIT 1`,
		userID, req.CompanionID).Scan(&conversationID)
	if err == nil {
		c.JSON(http.StatusOK, gin.H{"conversation_id": conversationID})
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
	c.JSON(http.StatusCreated, gin.H{"conversation_id": conversationID})
}

func GetTodayLife(c *gin.Context) {
	companionID := c.Param("id")
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
	c.JSON(http.StatusOK, gin.H{"memories": memories})
}

func UploadMedia(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"url": "https://storage.example.com/uploaded"})
}

func GenerateMedia(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"job_id": uuid.New().String(), "status": "queued"})
}

// --- Token Generation ---

type Claims struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

func parseUUID(s string) uuid.UUID {
	u, _ := uuid.Parse(s)
	return u
}

func generateToken(userID uuid.UUID, role string) (string, error) {
	claims := Claims{
		UserID: userID.String(),
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(jwtSecret))
}

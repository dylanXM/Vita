package handler

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"vita/internal/auth"
	"vita/internal/db"
)

const jwtSecret = "dev-secret-change-me-32-characters-min"
const codeLength = 6
const codeTTL = 5 * time.Minute

var rdb *redis.Client

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
		_, err = db.Get().Exec(`INSERT INTO users (id, email, role_id) VALUES ($1, $2, 'user')`, userID, req.Email)
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

	// Log the code (in production, send via email/SMS)
	fmt.Printf("[SMS/EMAIL] Verification code for %s: %s (expires in %v)\n", req.Email, code, codeTTL)

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
	_, err = db.Get().Exec(`INSERT INTO users (id, email, role_id) VALUES ($1, $2, 'user')`, userID, req.Email)
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

// AppLogin - login endpoint for mobile app
type AppLoginRequest struct {
	Email string `json:"email" binding:"required,email"`
	Code  string `json:"code" binding:"required,len=6"`
}

type AppLoginResponse struct {
	UserID string `json:"user_id"`
	Token  string `json:"token"`
	Role   string `json:"role"`
}

func AppLogin(c *gin.Context) {
	// Same as Login but returns app-specific response
	var req AppLoginRequest
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

	c.JSON(http.StatusOK, AppLoginResponse{UserID: userID, Token: token, Role: role})
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
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

type CreateCompanionRequest struct {
	Name              string `json:"name" binding:"required"`
	Gender            string `json:"gender"`
	Persona           string `json:"persona"`
	Appearance        string `json:"appearance"`
	City              string `json:"city"`
	Occupation        string `json:"occupation"`
	Interests         string `json:"interests"`
	RelationshipStage string `json:"relationship_stage"`
}

func CreateCompanion(c *gin.Context) {
	var req CreateCompanionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	companionID := uuid.New().String()
	userID := c.GetString("user_id")
	if userID == "" {
		userID = uuid.New().String()
	}
	query := `INSERT INTO companions (id, user_id, name, gender, persona, appearance, city, occupation, interests, relationship_stage) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`
	_, err := db.Get().Exec(query, companionID, userID, req.Name, req.Gender, req.Persona, req.Appearance, req.City, req.Occupation, req.Interests, req.RelationshipStage)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create companion"})
		return
	}
	c.JSON(http.StatusCreated, Companion{
		ID: companionID, UserID: userID, Name: req.Name,
		Gender: req.Gender, Persona: req.Persona,
		RelationshipStage: req.RelationshipStage,
	})
}

func GetCompanion(c *gin.Context) {
	id := c.Param("id")
	var comp Companion
	err := db.Get().QueryRow(`SELECT id, user_id, name, gender, persona, appearance, city, occupation, interests, relationship_stage, created_at, updated_at FROM companions WHERE id = $1`, id).Scan(
		&comp.ID, &comp.UserID, &comp.Name, &comp.Gender, &comp.Persona, &comp.Appearance, &comp.City, &comp.Occupation, &comp.Interests, &comp.RelationshipStage, &comp.CreatedAt, &comp.UpdatedAt,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	c.JSON(http.StatusOK, comp)
}

func ListCompanions(c *gin.Context) {
	rows, err := db.Get().Query(`SELECT id, user_id, name, gender, persona, appearance, city, occupation, interests, relationship_stage, created_at, updated_at FROM companions ORDER BY created_at DESC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list companions"})
		return
	}
	defer rows.Close()
	var companions []Companion
	for rows.Next() {
		var comp Companion
		rows.Scan(&comp.ID, &comp.UserID, &comp.Name, &comp.Gender, &comp.Persona, &comp.Appearance, &comp.City, &comp.Occupation, &comp.Interests, &comp.RelationshipStage, &comp.CreatedAt, &comp.UpdatedAt)
		companions = append(companions, comp)
	}
	c.JSON(http.StatusOK, companions)
}

func UpdateCompanion(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "companion updated"})
}

func DeleteCompanion(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "companion deleted"})
}

type SendMessageRequest struct {
	Content     string `json:"content" binding:"required"`
	MessageType string `json:"message_type"`
}

type SendMessageResponse struct {
	ID      string    `json:"id"`
	Content string    `json:"content"`
	Sender  string    `json:"sender"`
	Created time.Time `json:"created_at"`
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
	if userID == "" {
		userID = uuid.New().String()
	}
	query := `INSERT INTO messages (id, conversation_id, sender_type, message_type, content, created_at) VALUES ($1, $2, $3, $4, $5, $6)`
	_, err := db.Get().Exec(query, msgID, conversationID, "user", req.MessageType, req.Content, time.Now())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send message"})
		return
	}
	c.JSON(http.StatusCreated, SendMessageResponse{ID: msgID, Content: req.Content, Sender: "user", Created: time.Now()})
}

func GetMessages(c *gin.Context) {
	conversationID := c.Param("id")
	rows, err := db.Get().Query(`SELECT id, conversation_id, sender_type, message_type, content, media_url, created_at FROM messages WHERE conversation_id = $1 ORDER BY created_at ASC`, conversationID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get messages"})
		return
	}
	defer rows.Close()
	var messages []map[string]interface{}
	for rows.Next() {
		var m map[string]interface{}
		var id, conversationID, senderType, messageType, content, mediaURL string
		var created time.Time
		rows.Scan(&id, &conversationID, &senderType, &messageType, &content, &mediaURL, &created)
		m = map[string]interface{}{"id": id, "conversation_id": conversationID, "sender_type": senderType, "message_type": messageType, "content": content, "media_url": mediaURL, "created_at": created}
		messages = append(messages, m)
	}
	c.JSON(http.StatusOK, messages)
}

func GetTodayLife(c *gin.Context) {
	companionID := c.Param("id")
	rows, err := db.Get().Query(`SELECT id, event_type, title, description, location, start_time, end_time, emotion, importance FROM life_events WHERE companion_id = $1 AND DATE(start_time) = CURRENT_DATE ORDER BY start_time`, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get today's life"})
		return
	}
	defer rows.Close()
	var events []map[string]interface{}
	for rows.Next() {
		var id, eventType, title, description, location string
		var startTime, endTime time.Time
		var emotion, importance int
		rows.Scan(&id, &eventType, &title, &description, &location, &startTime, &endTime, &emotion, &importance)
		m := map[string]interface{}{
			"id": id, "event_type": eventType, "title": title,
			"description": description, "location": location,
			"start_time": startTime, "end_time": endTime,
			"emotion": emotion, "importance": importance,
		}
		events = append(events, m)
	}
	c.JSON(http.StatusOK, events)
}

func GetLifeEvents(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"events": []interface{}{}})
}

func GetMemories(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"memories": []interface{}{}})
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

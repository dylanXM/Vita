package handler

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"vita/internal/db"
	"vita/internal/storage"
)

const jwtSecret = "dev-secret-change-me-32-characters-min"

type HealthResponse struct {
	Status  string `json:"status"`
	Version string `json:"version"`
}

func Health(c *gin.Context) {
	c.JSON(http.StatusOK, HealthResponse{Status: "ok", Version: "0.1.0"})
}

type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
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
	userID := uuid.New().String()
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 14)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}
	query := `INSERT INTO users (id, email, password_hash) VALUES ($1, $2, $3)`
	_, err = db.Get().Exec(query, userID, req.Email, passwordHash)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "email already exists"})
		return
	}
	token, err := generateToken(uuid.MustParse(userID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}
	c.JSON(http.StatusCreated, RegisterResponse{UserID: userID, Token: token})
}

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type LoginResponse struct {
	UserID string `json:"user_id"`
	Token  string `json:"token"`
}

func Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var userID, passwordHash string
	err := db.Get().QueryRow(`SELECT id, password_hash FROM users WHERE email = $1`, req.Email).Scan(&userID, &passwordHash)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}
	if !bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)) != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}
	token, err := generateToken(uuid.MustParse(userID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}
	c.JSON(http.StatusOK, LoginResponse{UserID: userID, Token: token})
}

func Logout(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "logged out"})
}

func RefreshToken(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"token": "new_token_placeholder"})
}

type Companion struct {
	ID              string    `json:"id"`
	UserID          string    `json:"user_id"`
	Name            string    `json:"name"`
	Gender          string    `json:"gender"`
	Persona         string    `json:"persona"`
	Appearance      string    `json:"appearance"`
	City            string    `json:"city"`
	Occupation      string    `json:"occupation"`
	Interests       string    `json:"interests"`
	RelationshipStage string  `json:"relationship_stage"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type CreateCompanionRequest struct {
	Name             string `json:"name" binding:"required"`
	Gender           string `json:"gender"`
	Persona          string `json:"persona"`
	Appearance       string `json:"appearance"`
	City             string `json:"city"`
	Occupation       string `json:"occupation"`
	Interests        string `json:"interests"`
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
		var m map[string]interface{}
		rows.Scan(&m["id"], &m["event_type"], &m["title"], &m["description"], &m["location"], &m["start_time"], &m["end_time"], &m["emotion"], &m["importance"])
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

func generateToken(userID uuid.UUID) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id": userID.String(),
		"exp":     time.Now().Add(24 * time.Hour).Unix(),
	})
	return token.SignedString([]byte(jwtSecret))
}

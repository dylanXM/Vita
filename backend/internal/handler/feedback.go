package handler

import (
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"vita/internal/db"
)

func SubmitFeedback(c *gin.Context) {
	var req struct {
		Content string `json:"content"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid feedback"})
		return
	}
	content := strings.TrimSpace(req.Content)
	if n := utf8.RuneCountInString(content); n < 1 || n > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "feedback must contain 1–2000 characters"})
		return
	}
	id := uuid.New().String()
	if _, err := db.Get().ExecContext(c.Request.Context(), `INSERT INTO user_feedback(id,user_id,content) VALUES($1,$2,$3)`, id, c.GetString("user_id"), content); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save feedback"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": id})
}

func AdminListFeedback(c *gin.Context) {
	page, err := strconv.Atoi(c.DefaultQuery("page", "1"))
	if err != nil || page < 1 || page > 100000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid page"})
		return
	}
	rows, err := db.Get().QueryContext(c.Request.Context(), `SELECT f.id,f.user_id,u.email,u.environment,f.content,f.created_at FROM user_feedback f JOIN users u ON u.id=f.user_id ORDER BY f.created_at DESC,f.id DESC LIMIT 51 OFFSET $1`, (page-1)*50)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load feedback"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, userID, email, environment, content string
		var created time.Time
		if err := rows.Scan(&id, &userID, &email, &environment, &content, &created); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read feedback"})
			return
		}
		items = append(items, gin.H{"id": id, "user_id": userID, "email": email, "environment": environment, "content": content, "created_at": created})
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read feedback"})
		return
	}
	more := len(items) > 50
	if more {
		items = items[:50]
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "has_more": more})
}

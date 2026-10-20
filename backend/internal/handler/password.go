package handler

import (
	"context"
	"net/http"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"vita/internal/auth"
	"vita/internal/db"
)

func passwordResetKey(userID string) string {
	return "password-reset:" + currentEnvironment() + ":" + userID
}

func SendPasswordResetCode(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}
	if rdb == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "verification unavailable"})
		return
	}
	var email string
	if err := db.Get().QueryRow(`SELECT email FROM users WHERE id=$1`, userID).Scan(&email); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load account"})
		return
	}
	ctx := context.Background()
	key := passwordResetKey(userID)
	acquired, err := rdb.SetNX(ctx, key+":cooldown", "1", registerCooldown).Result()
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "verification unavailable"})
		return
	}
	if !acquired {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "please wait 60 seconds"})
		return
	}
	code, err := generateCode()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate code"})
		return
	}
	if err = rdb.Set(ctx, key, code, codeTTL).Err(); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "verification unavailable"})
		return
	}
	if err = mailCfg.SendVerificationCode(email, code); err != nil {
		rdb.Del(ctx, key)
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to send code"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "code sent"})
}

func ChangeMyPassword(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}
	var input struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
		Code            string `json:"code"`
	}
	if c.ShouldBindJSON(&input) != nil || utf8.RuneCountInString(input.NewPassword) < 6 || len(input.NewPassword) > 72 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "new password must contain at least 6 characters and at most 72 bytes"})
		return
	}
	var oldHash string
	if err := db.Get().QueryRow(`SELECT COALESCE(password_hash,'') FROM users WHERE id=$1`, userID).Scan(&oldHash); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load account"})
		return
	}
	if input.Code != "" {
		if rdb == nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "verification unavailable"})
			return
		}
		// One attempt consumes the code, preventing repeated guesses or replay.
		code, err := rdb.GetDel(context.Background(), passwordResetKey(userID)).Result()
		if err != nil || code != input.Code {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid or expired code"})
			return
		}
	} else if !auth.VerifyPassword(oldHash, input.CurrentPassword) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "current password is incorrect; use password reset if no password is set"})
		return
	}
	hash, err := auth.HashPassword(input.NewPassword)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}
	result, err := db.Get().Exec(`UPDATE users SET password_hash=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND COALESCE(password_hash,'')=$3`, hash, userID, oldHash)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update password"})
		return
	}
	count, err := result.RowsAffected()
	if err != nil || count != 1 {
		c.JSON(http.StatusConflict, gin.H{"error": "password changed; retry with current credentials"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "password changed"})
}

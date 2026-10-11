package handler

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"vita/internal/db"
)

// BindInvitation assigns an inviter once; the conditional write also prevents
// concurrent requests from replacing an existing binding.
func BindInvitation(c *gin.Context) {
	userID := c.GetString("user_id")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}
	var input struct {
		InviteCode string `json:"invite_code"`
	}
	if err := c.ShouldBindJSON(&input); err != nil || strings.TrimSpace(input.InviteCode) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invite code is required"})
		return
	}
	code := strings.ToUpper(strings.TrimSpace(input.InviteCode))
	var inviterID string
	err := db.Get().QueryRow(`SELECT inviter.id FROM users inviter JOIN users account ON account.environment=inviter.environment WHERE account.id=$1 AND inviter.invite_code=$2`, userID, code).Scan(&inviterID)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invite code"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load inviter"})
		return
	}
	if inviterID == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot bind your own invite code"})
		return
	}
	var id string
	err = db.Get().QueryRow(`UPDATE users SET invited_by_user_id=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND invited_by_user_id IS NULL RETURNING id`, inviterID, userID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusConflict, gin.H{"error": "invite code is already bound"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to bind invite code"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"bound_invite_code": code})
}

package handler

import (
	"math"
	"net/http"

	"github.com/gin-gonic/gin"

	"vita/internal/db"
)

type invitationSettingsResponse struct {
	RewardBasisPoints int     `json:"reward_basis_points"`
	RewardPercent     float64 `json:"reward_percent"`
	InvitedUsers      int     `json:"invited_users"`
	RewardedCoins     int     `json:"rewarded_coins"`
}

func loadInvitationSettings(environment string) (invitationSettingsResponse, error) {
	var output invitationSettingsResponse
	err := db.Get().QueryRow(`SELECT s.reward_basis_points,
		(SELECT COUNT(*) FROM users WHERE invited_by_user_id IS NOT NULL AND environment=$1),
		(SELECT COALESCE(SUM(r.reward_coins),0) FROM invitation_rewards r
		 JOIN users u ON u.id=r.invited_user_id WHERE u.environment=$1)
		FROM invitation_settings s WHERE s.environment=$1`, environment).Scan(
		&output.RewardBasisPoints, &output.InvitedUsers, &output.RewardedCoins)
	output.RewardPercent = float64(output.RewardBasisPoints) / 100
	return output, err
}

func AdminGetInvitationSettings(c *gin.Context) {
	settings, err := loadInvitationSettings(currentEnvironment())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load invitation settings"})
		return
	}
	c.JSON(http.StatusOK, settings)
}

func AdminUpdateInvitationSettings(c *gin.Context) {
	var input struct {
		RewardPercent float64 `json:"reward_percent" binding:"gte=0,lte=100"`
	}
	if err := c.ShouldBindJSON(&input); err != nil || math.IsNaN(input.RewardPercent) || math.IsInf(input.RewardPercent, 0) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reward percent must be between 0 and 100"})
		return
	}
	basisPoints := int(math.Round(input.RewardPercent * 100))
	if _, err := db.Get().Exec(`UPDATE invitation_settings SET reward_basis_points=$1,updated_at=CURRENT_TIMESTAMP WHERE environment=$2`, basisPoints, currentEnvironment()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save invitation settings"})
		return
	}
	settings, err := loadInvitationSettings(currentEnvironment())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reload invitation settings"})
		return
	}
	c.JSON(http.StatusOK, settings)
}

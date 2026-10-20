package handler

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"vita/internal/agent"
	"vita/internal/db"
)

func UploadCharacterImage(c *gin.Context) {
	c.Set("character_image", true)
	UploadMedia(c)
}

func validateCharacterImage(c *gin.Context, data []byte, mime string) bool {
	if !strings.HasPrefix(mime, "image/") {
		c.JSON(400, gin.H{"error": "character image is required", "code": "character_image_invalid"})
		return false
	}
	if companionAgent == nil {
		c.JSON(503, gin.H{"error": "image validation unavailable", "code": "character_image_validation_unavailable"})
		return false
	}
	err := companionAgent.ValidateCharacterImage(c.Request.Context(), c.GetString("user_id"), data, mime)
	if errors.Is(err, agent.ErrNotSinglePerson) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "upload an image of a single human character", "code": "character_image_invalid"})
		return false
	}
	if err != nil {
		c.JSON(503, gin.H{"error": "image validation unavailable; please retry", "code": "character_image_validation_unavailable"})
		return false
	}
	return true
}

func markCharacterImage(c *gin.Context, id string) bool {
	_, err := db.Get().ExecContext(c.Request.Context(), `UPDATE media_assets SET character_image_validated=true WHERE id=$1 AND user_id=$2 AND kind='image'`, id, c.GetString("user_id"))
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to save image validation", "code": "character_image_validation_unavailable"})
		return false
	}
	return true
}

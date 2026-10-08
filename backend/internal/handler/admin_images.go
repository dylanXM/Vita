package handler

import (
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/storage"
)

var adminImageBaseURL string

func InitAdminImageBaseURL(value string) { adminImageBaseURL = strings.TrimRight(value, "/") }

func validArtworkURL(value string) bool {
	if strings.HasPrefix(value, "asset://assets/") {
		return true
	}
	parsed, err := url.Parse(value)
	return err == nil && (parsed.Scheme == "http" || parsed.Scheme == "https") && parsed.Host != "" && parsed.User == nil
}

// AdminUploadImage stores artwork that must be readable by every app user.
// Private user uploads remain available only through /v1/media/:id.
func AdminUploadImage(c *gin.Context) {
	if mediaStorage == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "media storage is unavailable"})
		return
	}
	const maxImageSize = 10 << 20
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxImageSize+(1<<20))
	file, _, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image file is required (maximum 10 MB)"})
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxImageSize+1))
	if err != nil || len(data) == 0 || len(data) > maxImageSize {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image must contain 1 byte to 10 MB"})
		return
	}
	mimeType := http.DetectContentType(data)
	switch mimeType {
	case "image/png", "image/jpeg", "image/webp", "image/gif":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "image must be PNG, JPEG, WebP or GIF"})
		return
	}
	id := uuid.New().String()
	if err := mediaStorage.StoreAdminImage(c.Request.Context(), id, mimeType, data); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to store image"})
		return
	}
	scheme := "http"
	if c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https") {
		scheme = "https"
	}
	baseURL := adminImageBaseURL
	if baseURL == "" {
		baseURL = scheme + "://" + c.Request.Host
	}
	c.JSON(http.StatusCreated, gin.H{"url": baseURL + "/v1/admin-images/" + id})
}

func GetAdminImage(c *gin.Context) {
	if mediaStorage == nil {
		c.Status(http.StatusServiceUnavailable)
		return
	}
	media, err := mediaStorage.OpenAdminImage(c.Request.Context(), c.Param("id"))
	if errors.Is(err, storage.ErrNotFound) {
		c.Status(http.StatusNotFound)
		return
	}
	if err != nil {
		c.Status(http.StatusBadGateway)
		return
	}
	defer media.Body.Close()
	c.Header("Cache-Control", "public, max-age=31536000, immutable")
	c.Header("X-Content-Type-Options", "nosniff")
	c.DataFromReader(http.StatusOK, media.Size, media.MimeType, media.Body, nil)
}

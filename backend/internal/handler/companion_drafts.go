package handler

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ledongthuc/pdf"

	"vita/internal/db"
)

const (
	maxCharacterImageBytes    = 10 << 20
	maxCharacterDocumentBytes = 12 << 20
	maxCharacterSourceRunes   = 60000
)

// GenerateCompanionDraft creates an editable profile. It does not create a
// companion; the app must let the user review and submit the returned fields.
func GenerateCompanionDraft(c *gin.Context) {
	if companionAgent == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "character generation is unavailable"})
		return
	}
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
	if err := c.Request.ParseMultipartForm(maxCharacterImageBytes + maxCharacterDocumentBytes + (1 << 20)); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid character draft request"})
		return
	}
	if c.Request.MultipartForm != nil {
		defer c.Request.MultipartForm.RemoveAll()
	}

	mode := strings.TrimSpace(c.PostForm("mode"))
	characterName := strings.TrimSpace(c.PostForm("character_name"))
	var source string
	switch mode {
	case "user_description":
		source = strings.TrimSpace(c.PostForm("description"))
		if source == "" || utf8.RuneCountInString(source) > 4000 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "description must contain 1 to 4000 characters"})
			return
		}
	case "meet_file":
		if characterName == "" || utf8.RuneCountInString(characterName) > 100 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "character name must contain 1 to 100 characters"})
			return
		}
		document, header, fileErr := c.Request.FormFile("document")
		if fileErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "PDF, DOCX, or TXT document is required"})
			return
		}
		defer document.Close()
		data, readErr := readLimitedFile(document, maxCharacterDocumentBytes)
		if readErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": readErr.Error()})
			return
		}
		source, readErr = extractCharacterDocument(header.Filename, data)
		if readErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": readErr.Error()})
			return
		}
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported character creation mode"})
		return
	}

	image, _, err := c.Request.FormFile("image")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "character image is required"})
		return
	}
	defer image.Close()
	imageData, err := readLimitedFile(image, maxCharacterImageBytes)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	mimeType := http.DetectContentType(imageData)
	if !strings.HasPrefix(mimeType, "image/") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "character image has an invalid content type"})
		return
	}

	profile, err := companionAgent.GenerateCharacterProfile(c.Request.Context(), userID, mode, source, characterName)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to generate character profile"})
		return
	}
	mediaID := uuid.New().String()
	if _, err := db.Get().ExecContext(c.Request.Context(), `INSERT INTO media_assets(id,user_id,kind,mime_type,data,size_bytes) VALUES($1,$2,'image',$3,$4,$5)`, mediaID, userID, mimeType, imageData, len(imageData)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to store character image"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"profile": profile, "avatar_media_id": mediaID,
		"portrait_url": "/v1/media/" + mediaID, "creation_source": mode,
	})
}

func readLimitedFile(file multipart.File, limit int64) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil || len(data) == 0 || int64(len(data)) > limit {
		return nil, fmt.Errorf("file must contain 1 byte to %d MB", limit>>20)
	}
	return data, nil
}

func extractCharacterDocument(filename string, data []byte) (string, error) {
	var text string
	var err error
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".txt":
		if !utf8.Valid(data) {
			return "", errors.New("TXT document must use UTF-8 encoding")
		}
		text = string(data)
	case ".docx":
		text, err = extractDOCXText(data)
	case ".pdf":
		reader, openErr := pdf.NewReader(bytes.NewReader(data), int64(len(data)))
		if openErr != nil {
			err = openErr
			break
		}
		plain, plainErr := reader.GetPlainText()
		if plainErr != nil {
			err = plainErr
			break
		}
		var raw []byte
		raw, err = io.ReadAll(io.LimitReader(plain, maxCharacterDocumentBytes))
		text = string(raw)
	default:
		return "", errors.New("document must be PDF, DOCX, or TXT")
	}
	if err != nil {
		return "", errors.New("document text could not be extracted")
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return "", errors.New("document contains no readable text")
	}
	runes := []rune(text)
	if len(runes) > maxCharacterSourceRunes {
		text = string(runes[:maxCharacterSourceRunes])
	}
	return text, nil
}

func extractDOCXText(data []byte) (string, error) {
	archive, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return "", err
	}
	for _, file := range archive.File {
		if file.Name != "word/document.xml" {
			continue
		}
		stream, err := file.Open()
		if err != nil {
			return "", err
		}
		defer stream.Close()
		decoder := xml.NewDecoder(io.LimitReader(stream, maxCharacterDocumentBytes))
		var parts []string
		for {
			token, err := decoder.Token()
			if errors.Is(err, io.EOF) {
				break
			}
			if err != nil {
				return "", err
			}
			start, ok := token.(xml.StartElement)
			if !ok || start.Name.Local != "t" {
				continue
			}
			var value string
			if err := decoder.DecodeElement(&value, &start); err != nil {
				return "", err
			}
			if value = strings.TrimSpace(value); value != "" {
				parts = append(parts, value)
			}
		}
		return strings.Join(parts, " "), nil
	}
	return "", errors.New("DOCX document has no word/document.xml")
}

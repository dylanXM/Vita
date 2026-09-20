package handler

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/config"
	"vita/internal/db"
)

type legalDocument struct {
	ID           string     `json:"id"`
	Environment  string     `json:"environment"`
	DocumentType string     `json:"document_type"`
	Version      string     `json:"version"`
	Title        string     `json:"title"`
	Summary      string     `json:"summary"`
	Content      string     `json:"content"`
	IsEffective  bool       `json:"is_effective"`
	PublishedAt  *time.Time `json:"published_at"`
	UpdatedBy    string     `json:"updated_by"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

type appLegalDocument struct {
	ID           string    `json:"id"`
	DocumentType string    `json:"document_type"`
	Version      string    `json:"version"`
	Title        string    `json:"title"`
	Summary      string    `json:"summary"`
	Content      string    `json:"content"`
	UpdatedAt    time.Time `json:"updated_at"`
}

func legalDocumentsForApp(items map[string]legalDocument) map[string]appLegalDocument {
	output := make(map[string]appLegalDocument, len(items))
	for key, item := range items {
		output[key] = appLegalDocument{
			ID: item.ID, DocumentType: item.DocumentType, Version: item.Version,
			Title: item.Title, Summary: item.Summary, Content: item.Content, UpdatedAt: item.UpdatedAt,
		}
	}
	return output
}

var (
	errLegalConsentRequired = errors.New("privacy policy and terms must be accepted")
	errLegalUnavailable     = errors.New("legal documents are not configured")
	errLegalVersionChanged  = errors.New("legal documents have changed; review and accept the latest versions")
)

func validLegalDocumentType(value string) bool { return value == "privacy" || value == "terms" }

func scanLegalDocument(scanner interface{ Scan(...any) error }) (legalDocument, error) {
	var item legalDocument
	err := scanner.Scan(&item.ID, &item.Environment, &item.DocumentType, &item.Version,
		&item.Title, &item.Summary, &item.Content, &item.IsEffective, &item.PublishedAt,
		&item.UpdatedBy, &item.CreatedAt, &item.UpdatedAt)
	return item, err
}

const legalDocumentColumns = `id,environment,document_type,version,title,summary,content,is_effective,published_at,updated_by,created_at,updated_at`

func activeLegalDocuments(environment string) (map[string]legalDocument, error) {
	rows, err := db.Get().Query(`SELECT `+legalDocumentColumns+` FROM legal_documents
		WHERE environment=$1 AND is_effective=true`, environment)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make(map[string]legalDocument, 2)
	for rows.Next() {
		item, err := scanLegalDocument(rows)
		if err != nil {
			return nil, err
		}
		items[item.DocumentType] = item
	}
	return items, rows.Err()
}

func legalAcceptance(accepted *bool, privacyVersion, termsVersion string) (*time.Time, error) {
	acceptedAt, err := registrationLegalAcceptance(accepted)
	if err != nil {
		return nil, err
	}
	documents, err := activeLegalDocuments(currentEnvironment())
	if err != nil {
		return nil, errLegalUnavailable
	}
	privacy, privacyOK := documents["privacy"]
	terms, termsOK := documents["terms"]
	if !privacyOK || !termsOK {
		return nil, errLegalUnavailable
	}
	if strings.TrimSpace(privacyVersion) != privacy.Version || strings.TrimSpace(termsVersion) != terms.Version {
		return nil, errLegalVersionChanged
	}
	return acceptedAt, nil
}

func writeLegalAcceptanceError(c *gin.Context, err error) {
	status := http.StatusBadRequest
	code := "legal_consent_required"
	if errors.Is(err, errLegalUnavailable) {
		status = http.StatusServiceUnavailable
		code = "legal_documents_unavailable"
	} else if errors.Is(err, errLegalVersionChanged) {
		status = http.StatusConflict
		code = "legal_version_changed"
	}
	c.JSON(status, gin.H{"error": err.Error(), "code": code})
}

func AdminListLegalDocuments(c *gin.Context) {
	environment := strings.TrimSpace(c.Query("environment"))
	documentType := strings.TrimSpace(c.Query("document_type"))
	if !config.IsValidEnvironment(environment) || (documentType != "" && !validLegalDocumentType(documentType)) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "a valid environment and document type are required"})
		return
	}
	query := `SELECT ` + legalDocumentColumns + ` FROM legal_documents WHERE environment=$1`
	args := []any{environment}
	if documentType != "" {
		query += ` AND document_type=$2`
		args = append(args, documentType)
	}
	query += ` ORDER BY document_type, is_effective DESC, updated_at DESC`
	rows, err := db.Get().Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list legal documents"})
		return
	}
	defer rows.Close()
	items := make([]legalDocument, 0)
	for rows.Next() {
		item, scanErr := scanLegalDocument(rows)
		if scanErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read legal documents"})
			return
		}
		items = append(items, item)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func bindLegalDocument(c *gin.Context) (legalDocument, bool) {
	var input legalDocument
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid legal document"})
		return input, false
	}
	input.Environment = strings.TrimSpace(input.Environment)
	input.DocumentType = strings.TrimSpace(input.DocumentType)
	input.Version = strings.TrimSpace(input.Version)
	input.Title = strings.TrimSpace(input.Title)
	input.Summary = strings.TrimSpace(input.Summary)
	input.Content = strings.TrimSpace(input.Content)
	if !config.IsValidEnvironment(input.Environment) || !validLegalDocumentType(input.DocumentType) ||
		input.Version == "" || input.Title == "" || input.Content == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "environment, type, version, title, and content are required"})
		return input, false
	}
	return input, true
}

func AdminCreateLegalDocument(c *gin.Context) {
	input, ok := bindLegalDocument(c)
	if !ok {
		return
	}
	input.ID = uuid.NewString()
	_, err := db.Get().Exec(`INSERT INTO legal_documents(id,environment,document_type,version,title,summary,content,updated_by)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, input.ID, input.Environment, input.DocumentType,
		input.Version, input.Title, input.Summary, input.Content, contentOperator(c))
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "that legal document version already exists"})
		return
	}
	item, _ := scanLegalDocument(db.Get().QueryRow(`SELECT `+legalDocumentColumns+` FROM legal_documents WHERE id=$1`, input.ID))
	c.JSON(http.StatusCreated, item)
}

func AdminUpdateLegalDocument(c *gin.Context) {
	input, ok := bindLegalDocument(c)
	if !ok {
		return
	}
	result, err := db.Get().Exec(`UPDATE legal_documents SET environment=$2,document_type=$3,version=$4,title=$5,summary=$6,content=$7,updated_by=$8,updated_at=CURRENT_TIMESTAMP
		WHERE id=$1 AND published_at IS NULL`, c.Param("id"), input.Environment, input.DocumentType,
		input.Version, input.Title, input.Summary, input.Content, contentOperator(c))
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "that legal document version already exists"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "published legal documents cannot be modified"})
		return
	}
	item, _ := scanLegalDocument(db.Get().QueryRow(`SELECT `+legalDocumentColumns+` FROM legal_documents WHERE id=$1`, c.Param("id")))
	c.JSON(http.StatusOK, item)
}

func AdminActivateLegalDocument(c *gin.Context) {
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to activate legal document"})
		return
	}
	defer tx.Rollback()
	var environment, documentType string
	err = tx.QueryRow(`SELECT environment,document_type FROM legal_documents WHERE id=$1 FOR UPDATE`, c.Param("id")).Scan(&environment, &documentType)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "legal document not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to activate legal document"})
		return
	}
	if _, err = tx.Exec(`UPDATE legal_documents SET is_effective=false WHERE environment=$1 AND document_type=$2 AND is_effective=true`, environment, documentType); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to activate legal document"})
		return
	}
	if _, err = tx.Exec(`UPDATE legal_documents SET is_effective=true,published_at=COALESCE(published_at,CURRENT_TIMESTAMP),updated_by=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, c.Param("id"), contentOperator(c)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to activate legal document"})
		return
	}
	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to activate legal document"})
		return
	}
	item, _ := scanLegalDocument(db.Get().QueryRow(`SELECT `+legalDocumentColumns+` FROM legal_documents WHERE id=$1`, c.Param("id")))
	c.JSON(http.StatusOK, item)
}

func AdminDeleteLegalDocument(c *gin.Context) {
	result, err := db.Get().Exec(`DELETE FROM legal_documents WHERE id=$1 AND published_at IS NULL`, c.Param("id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete legal document"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "published legal documents cannot be deleted"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "legal document deleted"})
}

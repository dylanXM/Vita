package handler

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"vita/internal/db"
	mediastore "vita/internal/storage"
)

var mediaStorage *mediastore.Service

func InitMediaStorage(service *mediastore.Service) { mediaStorage = service }

type adminStorageProvider struct {
	Enabled             bool   `json:"enabled"`
	Endpoint            string `json:"endpoint"`
	Bucket              string `json:"bucket"`
	Region              string `json:"region"`
	AccessKeyConfigured bool   `json:"access_key_configured"`
	SecretKeyConfigured bool   `json:"secret_key_configured"`
}

type adminStorageConfig struct {
	Environment    string               `json:"environment"`
	ActiveProvider string               `json:"active_provider"`
	R2             adminStorageProvider `json:"r2"`
	COS            adminStorageProvider `json:"cos"`
}

type adminStorageProviderInput struct {
	Enabled   bool   `json:"enabled"`
	Endpoint  string `json:"endpoint"`
	Bucket    string `json:"bucket"`
	Region    string `json:"region"`
	AccessKey string `json:"access_key"`
	SecretKey string `json:"secret_key"`
}

type adminStorageConfigInput struct {
	ActiveProvider string                    `json:"active_provider"`
	R2             adminStorageProviderInput `json:"r2"`
	COS            adminStorageProviderInput `json:"cos"`
}

func AdminGetStorageConfig(c *gin.Context) {
	environment, ok := adminBillingEnvironment(c)
	if !ok {
		return
	}
	result, err := loadAdminStorageConfig(c.Request.Context(), environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load media storage configuration"})
		return
	}
	c.JSON(http.StatusOK, result)
}

func AdminUpdateStorageConfig(c *gin.Context) {
	if mediaStorage == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "media storage service is unavailable"})
		return
	}
	environment, ok := adminBillingEnvironment(c)
	if !ok {
		return
	}
	var input adminStorageConfigInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.ActiveProvider = strings.ToLower(strings.TrimSpace(input.ActiveProvider))
	if !input.R2.Enabled && !input.COS.Enabled {
		input.ActiveProvider = mediastore.ProviderPostgres
	} else if input.ActiveProvider != mediastore.ProviderR2 && input.ActiveProvider != mediastore.ProviderCOS {
		c.JSON(http.StatusBadRequest, gin.H{"error": "active_provider must select an enabled R2 or COS configuration"})
		return
	}
	if (input.ActiveProvider == mediastore.ProviderR2 && !input.R2.Enabled) || (input.ActiveProvider == mediastore.ProviderCOS && !input.COS.Enabled) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "active_provider must be enabled"})
		return
	}

	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save media storage configuration"})
		return
	}
	defer tx.Rollback()
	for provider, value := range map[string]adminStorageProviderInput{
		mediastore.ProviderR2:  input.R2,
		mediastore.ProviderCOS: input.COS,
	} {
		if err := saveStorageProvider(c.Request.Context(), tx, environment, provider, value); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}
	if _, err := tx.ExecContext(c.Request.Context(), `INSERT INTO media_storage_settings(environment,active_provider,updated_at) VALUES($1,$2,CURRENT_TIMESTAMP) ON CONFLICT(environment) DO UPDATE SET active_provider=EXCLUDED.active_provider,updated_at=CURRENT_TIMESTAMP`, environment, input.ActiveProvider); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save media storage selection"})
		return
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save media storage configuration"})
		return
	}
	result, err := loadAdminStorageConfig(c.Request.Context(), environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "media storage configuration saved but could not be reloaded"})
		return
	}
	c.JSON(http.StatusOK, result)
}

func AdminTestStorageConfig(c *gin.Context) {
	if mediaStorage == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "media storage service is unavailable"})
		return
	}
	environment, ok := adminBillingEnvironment(c)
	if !ok {
		return
	}
	provider := strings.ToLower(strings.TrimSpace(c.Query("provider")))
	if provider != mediastore.ProviderR2 && provider != mediastore.ProviderCOS {
		c.JSON(http.StatusBadRequest, gin.H{"error": "provider must be r2 or cos"})
		return
	}
	if err := mediaStorage.TestProvider(c.Request.Context(), environment, provider); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "storage connection test failed: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"provider": provider, "success": true})
}

func saveStorageProvider(ctx context.Context, tx *sql.Tx, environment, provider string, input adminStorageProviderInput) error {
	input.Endpoint = strings.TrimRight(strings.TrimSpace(input.Endpoint), "/")
	input.Bucket = strings.TrimSpace(input.Bucket)
	input.Region = strings.TrimSpace(input.Region)
	if provider == mediastore.ProviderR2 && input.Region == "" {
		input.Region = "auto"
	}
	var oldAccess, oldSecret string
	err := tx.QueryRowContext(ctx, `SELECT access_key_ciphertext,secret_key_ciphertext FROM media_storage_configs WHERE environment=$1 AND provider=$2`, environment, provider).Scan(&oldAccess, &oldSecret)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return errors.New("failed to load existing storage credentials")
	}
	accessCiphertext, secretCiphertext := oldAccess, oldSecret
	if strings.TrimSpace(input.AccessKey) != "" {
		accessCiphertext, err = mediaStorage.EncryptSecret(strings.TrimSpace(input.AccessKey))
		if err != nil {
			return errors.New("failed to protect storage access key")
		}
	}
	if input.SecretKey != "" {
		secretCiphertext, err = mediaStorage.EncryptSecret(input.SecretKey)
		if err != nil {
			return errors.New("failed to protect storage secret key")
		}
	}
	if input.Enabled {
		validation := mediastore.ProviderConfig{
			Provider: provider, Endpoint: input.Endpoint, Bucket: input.Bucket, Region: input.Region,
			AccessKey: credentialMarker(accessCiphertext), SecretKey: credentialMarker(secretCiphertext),
		}
		if err := mediastore.ValidateProviderConfig(validation); err != nil {
			return err
		}
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO media_storage_configs(environment,provider,enabled,endpoint,bucket,region,access_key_ciphertext,secret_key_ciphertext,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,CURRENT_TIMESTAMP) ON CONFLICT(environment,provider) DO UPDATE SET enabled=EXCLUDED.enabled,endpoint=EXCLUDED.endpoint,bucket=EXCLUDED.bucket,region=EXCLUDED.region,access_key_ciphertext=EXCLUDED.access_key_ciphertext,secret_key_ciphertext=EXCLUDED.secret_key_ciphertext,updated_at=CURRENT_TIMESTAMP`,
		environment, provider, input.Enabled, input.Endpoint, input.Bucket, input.Region, accessCiphertext, secretCiphertext)
	if err != nil {
		return errors.New("failed to save storage provider")
	}
	return nil
}

func credentialMarker(ciphertext string) string {
	if ciphertext == "" {
		return ""
	}
	return "configured"
}

func loadAdminStorageConfig(ctx context.Context, environment string) (adminStorageConfig, error) {
	result := adminStorageConfig{Environment: environment, ActiveProvider: mediastore.ProviderPostgres}
	err := db.Get().QueryRowContext(ctx, `SELECT active_provider FROM media_storage_settings WHERE environment=$1`, environment).Scan(&result.ActiveProvider)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return result, err
	}
	rows, err := db.Get().QueryContext(ctx, `SELECT provider,enabled,endpoint,bucket,region,access_key_ciphertext<>'',secret_key_ciphertext<>'' FROM media_storage_configs WHERE environment=$1`, environment)
	if err != nil {
		return result, err
	}
	defer rows.Close()
	for rows.Next() {
		var provider string
		var value adminStorageProvider
		if err := rows.Scan(&provider, &value.Enabled, &value.Endpoint, &value.Bucket, &value.Region, &value.AccessKeyConfigured, &value.SecretKeyConfigured); err != nil {
			return result, err
		}
		switch provider {
		case mediastore.ProviderR2:
			result.R2 = value
		case mediastore.ProviderCOS:
			result.COS = value
		}
	}
	return result, rows.Err()
}

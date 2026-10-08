package storage

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/url"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

const (
	ProviderPostgres = "postgres"
	ProviderR2       = "r2"
	ProviderCOS      = "cos"
)

var ErrNotFound = errors.New("media not found")

type ProviderConfig struct {
	Environment         string
	Provider            string
	Enabled             bool
	Endpoint            string
	Bucket              string
	Region              string
	AccessKeyCiphertext string
	SecretKeyCiphertext string
	AccessKey           string
	SecretKey           string
}

type Media struct {
	MimeType string
	Size     int64
	Body     io.ReadCloser
}

type objectClient interface {
	Put(context.Context, string, string, string, []byte) error
	Get(context.Context, string, string) (io.ReadCloser, int64, error)
	Delete(context.Context, string, string) error
}

type clientFactory func(context.Context, ProviderConfig) (objectClient, error)

type Service struct {
	db          *sql.DB
	environment string
	box         *secretBox
	newClient   clientFactory
}

func NewService(db *sql.DB, environment, encryptionKey string) (*Service, error) {
	box, err := newSecretBox(encryptionKey)
	if err != nil {
		return nil, err
	}
	return &Service{db: db, environment: environment, box: box, newClient: newS3Client}, nil
}

func (s *Service) EncryptSecret(value string) (string, error) { return s.box.encrypt(value) }

func (s *Service) Store(ctx context.Context, userID, id, kind, mimeType string, data []byte) error {
	provider, cfg, err := s.activeProvider(ctx)
	if err != nil {
		return err
	}
	if provider == ProviderPostgres {
		_, err = s.db.ExecContext(ctx, `INSERT INTO media_assets(id,user_id,kind,mime_type,data,size_bytes,storage_provider,object_key,storage_environment) VALUES($1,$2,$3,$4,$5,$6,'postgres','',$7)`,
			id, userID, kind, mimeType, data, len(data), s.environment)
		return err
	}

	client, err := s.newClient(ctx, cfg)
	if err != nil {
		return fmt.Errorf("create %s storage client: %w", provider, err)
	}
	objectKey := fmt.Sprintf("media/%s/%s/%s", s.environment, userID, id)
	if err := client.Put(ctx, cfg.Bucket, objectKey, mimeType, data); err != nil {
		return fmt.Errorf("upload media to %s: %w", provider, err)
	}
	if _, err := s.db.ExecContext(ctx, `INSERT INTO media_assets(id,user_id,kind,mime_type,data,size_bytes,storage_provider,object_key,storage_environment) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
		id, userID, kind, mimeType, []byte{}, len(data), provider, objectKey, s.environment); err != nil {
		_ = client.Delete(ctx, cfg.Bucket, objectKey)
		return err
	}
	return nil
}

// StoreAdminImage keeps public configuration artwork independent of the admin
// account that uploaded it, while using the environment's selected provider.
func (s *Service) StoreAdminImage(ctx context.Context, id, mimeType string, data []byte) error {
	provider, cfg, err := s.activeProvider(ctx)
	if err != nil {
		return err
	}
	if provider == ProviderPostgres {
		_, err = s.db.ExecContext(ctx, `INSERT INTO admin_images(id,mime_type,data,size_bytes,storage_provider,object_key,storage_environment)
			VALUES($1,$2,$3,$4,'postgres','',$5)`, id, mimeType, data, len(data), s.environment)
		return err
	}
	client, err := s.newClient(ctx, cfg)
	if err != nil {
		return fmt.Errorf("create %s storage client: %w", provider, err)
	}
	objectKey := fmt.Sprintf("admin-images/%s/%s", s.environment, id)
	if err := client.Put(ctx, cfg.Bucket, objectKey, mimeType, data); err != nil {
		return fmt.Errorf("upload admin image to %s: %w", provider, err)
	}
	if _, err := s.db.ExecContext(ctx, `INSERT INTO admin_images(id,mime_type,data,size_bytes,storage_provider,object_key,storage_environment)
		VALUES($1,$2,$3,$4,$5,$6,$7)`, id, mimeType, []byte{}, len(data), provider, objectKey, s.environment); err != nil {
		_ = client.Delete(ctx, cfg.Bucket, objectKey)
		return err
	}
	return nil
}

func (s *Service) OpenAdminImage(ctx context.Context, id string) (*Media, error) {
	var mimeType, provider, objectKey, environment string
	var data []byte
	var size int64
	err := s.db.QueryRowContext(ctx, `SELECT mime_type,data,size_bytes,storage_provider,object_key,storage_environment
		FROM admin_images WHERE id=$1`, id).Scan(&mimeType, &data, &size, &provider, &objectKey, &environment)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	if provider == ProviderPostgres {
		return &Media{MimeType: mimeType, Size: int64(len(data)), Body: io.NopCloser(bytes.NewReader(data))}, nil
	}
	cfg, err := s.providerConfig(ctx, environment, provider, false)
	if err != nil {
		return nil, err
	}
	client, err := s.newClient(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("create %s storage client: %w", provider, err)
	}
	body, remoteSize, err := client.Get(ctx, cfg.Bucket, objectKey)
	if err != nil {
		return nil, fmt.Errorf("download admin image from %s: %w", provider, err)
	}
	if remoteSize >= 0 {
		size = remoteSize
	}
	return &Media{MimeType: mimeType, Size: size, Body: body}, nil
}

func (s *Service) Open(ctx context.Context, id, userID string) (*Media, error) {
	var mimeType, provider, objectKey, environment string
	var data []byte
	var size int64
	err := s.db.QueryRowContext(ctx, `SELECT mime_type,data,size_bytes,storage_provider,object_key,storage_environment FROM media_assets WHERE id=$1 AND user_id=$2`, id, userID).
		Scan(&mimeType, &data, &size, &provider, &objectKey, &environment)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	if provider == "" || provider == ProviderPostgres {
		return &Media{MimeType: mimeType, Size: int64(len(data)), Body: io.NopCloser(bytes.NewReader(data))}, nil
	}
	cfg, err := s.providerConfig(ctx, environment, provider, false)
	if err != nil {
		return nil, err
	}
	client, err := s.newClient(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("create %s storage client: %w", provider, err)
	}
	body, remoteSize, err := client.Get(ctx, cfg.Bucket, objectKey)
	if err != nil {
		return nil, fmt.Errorf("download media from %s: %w", provider, err)
	}
	if remoteSize >= 0 {
		size = remoteSize
	}
	return &Media{MimeType: mimeType, Size: size, Body: body}, nil
}

func (s *Service) LoadBytes(ctx context.Context, id, userID string) (string, []byte, error) {
	media, err := s.Open(ctx, id, userID)
	if err != nil {
		return "", nil, err
	}
	defer media.Body.Close()
	data, err := io.ReadAll(media.Body)
	return media.MimeType, data, err
}

// MigrateLegacyMedia copies externally stored legacy media to the configured
// production provider before the database environment migration runs. Each
// row is changed only after its new object has been uploaded successfully.
// Old objects are retained for recovery.
func (s *Service) MigrateLegacyMedia(ctx context.Context) error {
	for _, table := range []string{"media_assets", "admin_images"} {
		for {
			query := `SELECT id FROM ` + table + ` WHERE storage_environment<>'prod' AND storage_provider IN ('r2','cos') ORDER BY id LIMIT 100`
			rows, err := s.db.QueryContext(ctx, query)
			if err != nil {
				return err
			}
			ids := make([]string, 0, 100)
			for rows.Next() {
				var id string
				if err := rows.Scan(&id); err != nil {
					rows.Close()
					return err
				}
				ids = append(ids, id)
			}
			if err := rows.Err(); err != nil {
				rows.Close()
				return err
			}
			rows.Close()
			if len(ids) == 0 {
				break
			}
			for _, id := range ids {
				if err := s.migrateLegacyMediaRow(ctx, table, id); err != nil {
					return fmt.Errorf("migrate %s %s: %w", table, id, err)
				}
			}
		}
	}
	for _, environment := range []string{"dev", "beta"} {
		legacy := *s
		legacy.environment = environment
		for {
			var count int
			if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM media_object_deletions WHERE environment=$1`, environment).Scan(&count); err != nil {
				return err
			}
			if count == 0 {
				break
			}
			if err := legacy.ProcessDeletionQueue(ctx, 100); err != nil {
				return err
			}
			var remaining int
			if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM media_object_deletions WHERE environment=$1`, environment).Scan(&remaining); err != nil {
				return err
			}
			if remaining >= count {
				return fmt.Errorf("legacy %s deletion queue has %d objects that could not be removed", environment, remaining)
			}
		}
	}
	return nil
}

func (s *Service) migrateLegacyMediaRow(ctx context.Context, table, id string) error {
	var userID string
	var mimeType string
	var body io.ReadCloser
	if table == "media_assets" {
		if err := s.db.QueryRowContext(ctx, `SELECT user_id FROM media_assets WHERE id=$1`, id).Scan(&userID); err != nil {
			return err
		}
		media, err := s.Open(ctx, id, userID)
		if err != nil {
			return err
		}
		mimeType, body = media.MimeType, media.Body
	} else {
		media, err := s.OpenAdminImage(ctx, id)
		if err != nil {
			return err
		}
		mimeType, body = media.MimeType, media.Body
	}
	data, err := io.ReadAll(body)
	body.Close()
	if err != nil {
		return err
	}
	provider, cfg, err := s.activeProvider(ctx)
	if err != nil {
		return err
	}
	if provider == ProviderPostgres {
		result, err := s.db.ExecContext(ctx, `UPDATE `+table+` SET data=$2,size_bytes=$3,storage_provider='postgres',object_key='',storage_environment='prod' WHERE id=$1 AND storage_environment<>'prod'`, id, data, len(data))
		return mediaMigrationUpdated(result, err)
	}
	client, err := s.newClient(ctx, cfg)
	if err != nil {
		return err
	}
	key := "admin-images/prod/" + id
	if table == "media_assets" {
		key = "media/prod/" + userID + "/" + id
	}
	if err := client.Put(ctx, cfg.Bucket, key, mimeType, data); err != nil {
		return err
	}
	result, err := s.db.ExecContext(ctx, `UPDATE `+table+` SET data=$2,size_bytes=$3,storage_provider=$4,object_key=$5,storage_environment='prod' WHERE id=$1 AND storage_environment<>'prod'`, id, []byte{}, len(data), provider, key)
	return mediaMigrationUpdated(result, err)
}

func mediaMigrationUpdated(result sql.Result, err error) error {
	if err != nil {
		return err
	}
	count, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if count != 1 {
		return fmt.Errorf("media row changed during migration")
	}
	return nil
}

func (s *Service) TestProvider(ctx context.Context, environment, provider string) error {
	cfg, err := s.providerConfig(ctx, environment, provider, false)
	if err != nil {
		return err
	}
	client, err := s.newClient(ctx, cfg)
	if err != nil {
		return err
	}
	key := fmt.Sprintf("_vita_storage_check/%s", randomToken())
	if err := client.Put(ctx, cfg.Bucket, key, "application/octet-stream", []byte("vita")); err != nil {
		return err
	}
	if err := client.Delete(ctx, cfg.Bucket, key); err != nil {
		return fmt.Errorf("test object uploaded but cleanup failed: %w", err)
	}
	return nil
}

func (s *Service) ProcessDeletionQueue(ctx context.Context, limit int) error {
	if limit <= 0 {
		limit = 50
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id,environment,storage_provider,object_key FROM media_object_deletions WHERE environment=$1 ORDER BY id LIMIT $2`, s.environment, limit)
	if err != nil {
		return err
	}
	type pending struct {
		id                         int64
		environment, provider, key string
	}
	var items []pending
	for rows.Next() {
		var item pending
		if err := rows.Scan(&item.id, &item.environment, &item.provider, &item.key); err != nil {
			rows.Close()
			return err
		}
		items = append(items, item)
	}
	if err := rows.Close(); err != nil {
		return err
	}
	for _, item := range items {
		cfg, configErr := s.providerConfig(ctx, item.environment, item.provider, false)
		if configErr == nil {
			var client objectClient
			client, configErr = s.newClient(ctx, cfg)
			if configErr == nil {
				configErr = client.Delete(ctx, cfg.Bucket, item.key)
			}
		}
		if configErr != nil {
			_, _ = s.db.ExecContext(ctx, `UPDATE media_object_deletions SET attempts=attempts+1,last_error=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, item.id, truncateError(configErr))
			continue
		}
		_, _ = s.db.ExecContext(ctx, `DELETE FROM media_object_deletions WHERE id=$1`, item.id)
	}
	return nil
}

func (s *Service) activeProvider(ctx context.Context) (string, ProviderConfig, error) {
	var active string
	err := s.db.QueryRowContext(ctx, `SELECT active_provider FROM media_storage_settings WHERE environment=$1`, s.environment).Scan(&active)
	if errors.Is(err, sql.ErrNoRows) {
		return ProviderPostgres, ProviderConfig{}, nil
	}
	if err != nil {
		return "", ProviderConfig{}, err
	}
	if active == ProviderR2 || active == ProviderCOS {
		cfg, configErr := s.providerConfig(ctx, s.environment, active, true)
		if configErr == nil {
			return active, cfg, nil
		}
		return "", ProviderConfig{}, configErr
	}
	var enabledCount int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM media_storage_configs WHERE environment=$1 AND enabled=true`, s.environment).Scan(&enabledCount); err != nil {
		return "", ProviderConfig{}, err
	}
	if enabledCount == 0 {
		return ProviderPostgres, ProviderConfig{}, nil
	}
	return "", ProviderConfig{}, errors.New("external media storage is enabled but no active provider is selected")
}

func (s *Service) providerConfig(ctx context.Context, environment, provider string, requireEnabled bool) (ProviderConfig, error) {
	if provider != ProviderR2 && provider != ProviderCOS {
		return ProviderConfig{}, fmt.Errorf("unsupported storage provider %q", provider)
	}
	cfg := ProviderConfig{Environment: environment, Provider: provider}
	err := s.db.QueryRowContext(ctx, `SELECT enabled,endpoint,bucket,region,access_key_ciphertext,secret_key_ciphertext FROM media_storage_configs WHERE environment=$1 AND provider=$2`, environment, provider).
		Scan(&cfg.Enabled, &cfg.Endpoint, &cfg.Bucket, &cfg.Region, &cfg.AccessKeyCiphertext, &cfg.SecretKeyCiphertext)
	if errors.Is(err, sql.ErrNoRows) {
		return ProviderConfig{}, fmt.Errorf("%s storage is not configured", provider)
	}
	if err != nil {
		return ProviderConfig{}, err
	}
	if requireEnabled && !cfg.Enabled {
		return ProviderConfig{}, fmt.Errorf("%s storage is disabled", provider)
	}
	cfg.AccessKey, err = s.box.decrypt(cfg.AccessKeyCiphertext)
	if err != nil {
		return ProviderConfig{}, fmt.Errorf("decrypt %s access key: %w", provider, err)
	}
	cfg.SecretKey, err = s.box.decrypt(cfg.SecretKeyCiphertext)
	if err != nil {
		return ProviderConfig{}, fmt.Errorf("decrypt %s secret key: %w", provider, err)
	}
	if err := ValidateProviderConfig(cfg); err != nil {
		return ProviderConfig{}, err
	}
	return cfg, nil
}

func ValidateProviderConfig(cfg ProviderConfig) error {
	if cfg.Provider != ProviderR2 && cfg.Provider != ProviderCOS {
		return errors.New("provider must be r2 or cos")
	}
	parsed, err := url.Parse(strings.TrimSpace(cfg.Endpoint))
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
		return fmt.Errorf("%s endpoint must be an HTTPS origin", cfg.Provider)
	}
	if strings.Trim(parsed.Path, "/") != "" {
		return fmt.Errorf("%s endpoint must not include a path", cfg.Provider)
	}
	host := strings.ToLower(parsed.Hostname())
	if cfg.Provider == ProviderR2 && !strings.HasSuffix(host, ".r2.cloudflarestorage.com") {
		return errors.New("r2 endpoint must use r2.cloudflarestorage.com")
	}
	if cfg.Provider == ProviderCOS && !strings.HasSuffix(host, ".myqcloud.com") {
		return errors.New("cos endpoint must use myqcloud.com")
	}
	if strings.TrimSpace(cfg.Bucket) == "" {
		return fmt.Errorf("%s bucket is required", cfg.Provider)
	}
	if strings.TrimSpace(cfg.Region) == "" {
		return fmt.Errorf("%s region is required", cfg.Provider)
	}
	if cfg.AccessKey == "" || cfg.SecretKey == "" {
		return fmt.Errorf("%s access key and secret key are required", cfg.Provider)
	}
	return nil
}

type s3ObjectClient struct {
	client *s3.Client
}

func newS3Client(ctx context.Context, cfg ProviderConfig) (objectClient, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion(cfg.Region),
		awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, "")),
	)
	if err != nil {
		return nil, err
	}
	client := s3.NewFromConfig(awsCfg, func(options *s3.Options) {
		options.BaseEndpoint = aws.String(strings.TrimRight(cfg.Endpoint, "/"))
		options.UsePathStyle = cfg.Provider == ProviderR2
	})
	return &s3ObjectClient{client: client}, nil
}

func (c *s3ObjectClient) Put(ctx context.Context, bucket, key, contentType string, data []byte) error {
	_, err := c.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(bucket), Key: aws.String(key), Body: bytes.NewReader(data),
		ContentLength: aws.Int64(int64(len(data))), ContentType: aws.String(contentType),
	})
	return err
}

func (c *s3ObjectClient) Get(ctx context.Context, bucket, key string) (io.ReadCloser, int64, error) {
	output, err := c.client.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String(bucket), Key: aws.String(key)})
	if err != nil {
		return nil, 0, err
	}
	return output.Body, aws.ToInt64(output.ContentLength), nil
}

func (c *s3ObjectClient) Delete(ctx context.Context, bucket, key string) error {
	_, err := c.client.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(bucket), Key: aws.String(key)})
	return err
}

type secretBox struct{ aead cipher.AEAD }

func newSecretBox(secret string) (*secretBox, error) {
	if secret == "" {
		return nil, errors.New("storage configuration encryption key is empty")
	}
	key := sha256.Sum256([]byte(secret))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &secretBox{aead: aead}, nil
}

func (b *secretBox) encrypt(value string) (string, error) {
	if value == "" {
		return "", nil
	}
	nonce := make([]byte, b.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b.aead.Seal(nonce, nonce, []byte(value), nil)), nil
}

func (b *secretBox) decrypt(value string) (string, error) {
	if value == "" {
		return "", nil
	}
	sealed, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return "", err
	}
	if len(sealed) < b.aead.NonceSize() {
		return "", errors.New("encrypted storage secret is truncated")
	}
	return stringValue(b.aead.Open(nil, sealed[:b.aead.NonceSize()], sealed[b.aead.NonceSize():], nil))
}

func stringValue(value []byte, err error) (string, error) {
	if err != nil {
		return "", err
	}
	return string(value), nil
}

func randomToken() string {
	raw := make([]byte, 12)
	if _, err := rand.Read(raw); err != nil {
		return "probe"
	}
	return base64.RawURLEncoding.EncodeToString(raw)
}

func truncateError(err error) string {
	message := err.Error()
	if len(message) > 1000 {
		return message[:1000]
	}
	return message
}

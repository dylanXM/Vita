package storage

import (
	"fmt"
	"vita/internal/config"
)

type Storage struct {
	cfg         *config.Config
	initialized bool
}

func New(cfg *config.Config) *Storage {
	return &Storage{cfg: cfg}
}

func (s *Storage) Init() error {
	if s.cfg.S3Bucket == "" {
		s.initialized = true
		return nil
	}
	fmt.Printf("storage initialized: provider=%s bucket=%s\n", s.cfg.StorageProvider, s.cfg.S3Bucket)
	s.initialized = true
	return nil
}

func (s *Storage) Upload(bucket, key string, data []byte) error {
	fmt.Printf("uploading %d bytes to %s/%s\n", len(data), bucket, key)
	return nil
}

func (s *Storage) PresignedURL(bucket, key string, expiry int64) (string, error) {
	return fmt.Sprintf("https://%s.s3.amazonaws.com/%s", bucket, key), nil
}

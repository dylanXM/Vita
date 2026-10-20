package storage

import (
	"strings"
	"testing"
)

func TestPresignedURLDoesNotDuplicateObjectKey(t *testing.T) {
	url, err := (&Storage{}).PresignedURL("vita-media", "companions/photo.png", 300)
	if err != nil {
		t.Fatal(err)
	}
	if url != "https://vita-media.s3.amazonaws.com/companions/photo.png" {
		t.Fatalf("url = %q", url)
	}
}

func TestSecretBoxRoundTrip(t *testing.T) {
	box, err := newSecretBox("test-encryption-key")
	if err != nil {
		t.Fatal(err)
	}
	encrypted, err := box.encrypt("secret-value")
	if err != nil {
		t.Fatal(err)
	}
	if encrypted == "secret-value" || encrypted == "" {
		t.Fatalf("secret was not encrypted: %q", encrypted)
	}
	decrypted, err := box.decrypt(encrypted)
	if err != nil {
		t.Fatal(err)
	}
	if decrypted != "secret-value" {
		t.Fatalf("decrypted = %q", decrypted)
	}
}

func TestValidateProviderConfig(t *testing.T) {
	valid := ProviderConfig{
		Provider: ProviderR2, Endpoint: "https://account.r2.cloudflarestorage.com",
		Bucket: "vita", Region: "auto", AccessKey: "key", SecretKey: "secret",
	}
	if err := ValidateProviderConfig(valid); err != nil {
		t.Fatalf("valid config: %v", err)
	}

	invalid := valid
	invalid.Endpoint = "http://account.r2.cloudflarestorage.com"
	if err := ValidateProviderConfig(invalid); err == nil || !strings.Contains(err.Error(), "HTTPS") {
		t.Fatalf("expected HTTPS validation error, got %v", err)
	}

	invalid = valid
	invalid.Endpoint = "https://account.r2.cloudflarestorage.com/path"
	if err := ValidateProviderConfig(invalid); err == nil || !strings.Contains(err.Error(), "path") {
		t.Fatalf("expected path validation error, got %v", err)
	}

	invalid = valid
	invalid.Endpoint = "https://storage.example.com"
	if err := ValidateProviderConfig(invalid); err == nil || !strings.Contains(err.Error(), "r2.cloudflarestorage.com") {
		t.Fatalf("expected R2 host validation error, got %v", err)
	}
}

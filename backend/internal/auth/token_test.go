package auth

import (
	"testing"
	"time"
)

func TestTokenManagerIssueAndParse(t *testing.T) {
	manager, err := NewTokenManager("test-secret-that-is-at-least-32-characters", 15*time.Minute, 24*time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	pair, err := manager.Issue("1a1cfa0b-cb6e-48ad-a380-cc5940bc381e", "user")
	if err != nil {
		t.Fatal(err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" || pair.ExpiresIn != 900 {
		t.Fatalf("unexpected token pair: %+v", pair)
	}
	access, err := manager.Parse(pair.AccessToken, TokenTypeAccess)
	if err != nil {
		t.Fatal(err)
	}
	refresh, err := manager.Parse(pair.RefreshToken, TokenTypeRefresh)
	if err != nil {
		t.Fatal(err)
	}
	if access.SessionID != refresh.SessionID || access.UserID != refresh.UserID {
		t.Fatal("token pair does not share the same session")
	}
	if _, err := manager.Parse(pair.RefreshToken, TokenTypeAccess); err == nil {
		t.Fatal("refresh token was accepted as an access token")
	}
}

func TestTokenManagerRejectsWeakConfiguration(t *testing.T) {
	if _, err := NewTokenManager("short", 15*time.Minute, 24*time.Hour); err == nil {
		t.Fatal("weak secret was accepted")
	}
	if _, err := NewTokenManager("test-secret-that-is-at-least-32-characters", time.Hour, time.Minute); err == nil {
		t.Fatal("invalid token lifetimes were accepted")
	}
}

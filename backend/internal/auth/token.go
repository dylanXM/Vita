package auth

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	TokenTypeAccess  = "access"
	TokenTypeRefresh = "refresh"
)

type Claims struct {
	UserID    string `json:"user_id"`
	Role      string `json:"role"`
	TokenType string `json:"token_type"`
	SessionID string `json:"session_id"`
	jwt.RegisteredClaims
}

type TokenPair struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    int64
}

type TokenManager struct {
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
	now        func() time.Time
}

func NewTokenManager(secret string, accessTTL, refreshTTL time.Duration) (*TokenManager, error) {
	if len(secret) < 32 {
		return nil, errors.New("JWT secret must contain at least 32 characters")
	}
	if accessTTL <= 0 || refreshTTL <= accessTTL {
		return nil, errors.New("refresh token TTL must be greater than access token TTL")
	}
	return &TokenManager{
		secret:     []byte(secret),
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
		now:        time.Now,
	}, nil
}

func (m *TokenManager) Issue(userID, role string) (TokenPair, error) {
	if _, err := uuid.Parse(userID); err != nil {
		return TokenPair{}, fmt.Errorf("invalid user id: %w", err)
	}
	sessionID := uuid.NewString()
	access, err := m.sign(userID, role, TokenTypeAccess, sessionID, m.accessTTL)
	if err != nil {
		return TokenPair{}, err
	}
	refresh, err := m.sign(userID, role, TokenTypeRefresh, sessionID, m.refreshTTL)
	if err != nil {
		return TokenPair{}, err
	}
	return TokenPair{AccessToken: access, RefreshToken: refresh, ExpiresIn: int64(m.accessTTL.Seconds())}, nil
}

func (m *TokenManager) Parse(raw, expectedType string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(raw, claims, func(token *jwt.Token) (any, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, fmt.Errorf("unexpected signing method %q", token.Method.Alg())
		}
		return m.secret, nil
	}, jwt.WithIssuer("vita"), jwt.WithExpirationRequired())
	if err != nil || !token.Valid {
		return nil, errors.New("invalid token")
	}
	if claims.TokenType != expectedType || claims.UserID == "" || claims.SessionID == "" || claims.ID == "" {
		return nil, errors.New("invalid token claims")
	}
	return claims, nil
}

func (m *TokenManager) RefreshTTL() time.Duration {
	return m.refreshTTL
}

func (m *TokenManager) sign(userID, role, tokenType, sessionID string, ttl time.Duration) (string, error) {
	now := m.now().UTC()
	claims := Claims{
		UserID:    userID,
		Role:      role,
		TokenType: tokenType,
		SessionID: sessionID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "vita",
			Subject:   userID,
			ID:        uuid.NewString(),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.secret)
}

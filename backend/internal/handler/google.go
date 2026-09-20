package handler

import (
	"crypto/rsa"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"vita/internal/db"
)

// --- Google sign-in (self-hosted OIDC) ---
//
// The mobile app obtains a Google ID token (google_sign_in) and posts it here.
// The backend verifies the token against Google's public JWKS — no Firebase, no
// Google SDK dependency — and issues the regular Vita JWT.

var (
	googleClientID string
	jwksMu         sync.Mutex
	jwksCache      *jwkSet
	jwksFetchedAt  time.Time
)

const (
	googleJWKSURL   = "https://www.googleapis.com/oauth2/v3/certs"
	googleIssuer    = "https://accounts.google.com"
	googleIssuerAlt = "accounts.google.com"
	jwksCacheTTL    = 1 * time.Hour
)

// SetGoogleClientID is called at startup with VITA_GOOGLE_CLIENT_ID.
func SetGoogleClientID(id string) { googleClientID = id }

type jwk struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type jwkSet struct {
	Keys []jwk `json:"keys"`
}

type GoogleClaims struct {
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	Name          string `json:"name"`
	Picture       string `json:"picture"`
	jwt.RegisteredClaims
}

type GoogleLoginRequest struct {
	IDToken       string `json:"id_token" binding:"required"`
	AcceptedLegal *bool  `json:"accepted_legal"`
}

type GoogleLoginResponse struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Role   string `json:"role"`
	TokenResponse
}

// GoogleLogin signs in (or registers) a user from a verified Google ID token.
func GoogleLogin(c *gin.Context) {
	var req GoogleLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if googleClientID == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "google sign-in is not configured"})
		return
	}

	claims, err := verifyGoogleIDToken(req.IDToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid google id token"})
		return
	}
	if !claims.EmailVerified || claims.Email == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "google email not verified"})
		return
	}

	var userID, role string
	err = db.Get().QueryRow(
		`SELECT id, COALESCE(role_id, 'user') FROM users WHERE email = $1`, claims.Email).
		Scan(&userID, &role)
	if errors.Is(err, sql.ErrNoRows) {
		acceptedAt, consentErr := registrationLegalAcceptance(req.AcceptedLegal)
		if consentErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": consentErr.Error(), "code": "legal_consent_required"})
			return
		}
		userID = uuid.New().String()
		role = "user"
		if _, err := db.Get().Exec(
			`INSERT INTO users (id,email,role_id,environment,legal_accepted_at,privacy_policy_version,terms_version)
			 VALUES ($1,$2,$3,$4,$5,$6,$7)`,
			userID, claims.Email, role, currentEnvironment(), acceptedAt, privacyPolicyVersion, termsVersion); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
			return
		}
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		return
	}

	if banned, err := userBanned(userID); err == nil && banned {
		c.JSON(http.StatusForbidden, gin.H{"error": "account is banned"})
		return
	}

	tokens, err := issueTokens(userID, role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}
	c.JSON(http.StatusOK, GoogleLoginResponse{
		UserID: userID, Email: claims.Email, Role: role, TokenResponse: tokens,
	})
}

func verifyGoogleIDToken(idToken string) (*GoogleClaims, error) {
	token, _, err := new(jwt.Parser).ParseUnverified(idToken, jwt.MapClaims{})
	if err != nil {
		return nil, err
	}
	kid, _ := token.Header["kid"].(string)
	if kid == "" {
		return nil, errors.New("token missing kid")
	}

	set, err := fetchJWKS()
	if err != nil {
		return nil, err
	}

	var pub *rsa.PublicKey
	for _, k := range set.Keys {
		if k.Kid == kid {
			pub, err = rsaPublicKey(k)
			if err != nil {
				return nil, err
			}
			break
		}
	}
	if pub == nil {
		return nil, errors.New("unknown signing key")
	}

	claims := &GoogleClaims{}
	parsed, err := jwt.ParseWithClaims(idToken, claims, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return pub, nil
	})
	if err != nil || !parsed.Valid {
		return nil, errors.New("invalid token")
	}
	if claims.Issuer != googleIssuer && claims.Issuer != googleIssuerAlt {
		return nil, errors.New("unexpected issuer")
	}
	audOK := false
	for _, aud := range claims.Audience {
		if aud == googleClientID {
			audOK = true
			break
		}
	}
	if !audOK {
		return nil, errors.New("unexpected audience")
	}
	return claims, nil
}

func fetchJWKS() (*jwkSet, error) {
	jwksMu.Lock()
	defer jwksMu.Unlock()

	if jwksCache != nil && time.Since(jwksFetchedAt) < jwksCacheTTL {
		return jwksCache, nil
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(googleJWKSURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("jwks endpoint returned %d", resp.StatusCode)
	}

	var set jwkSet
	if err := json.NewDecoder(resp.Body).Decode(&set); err != nil {
		return nil, err
	}
	jwksCache = &set
	jwksFetchedAt = time.Now()
	return &set, nil
}

func rsaPublicKey(k jwk) (*rsa.PublicKey, error) {
	nb, err := base64.RawURLEncoding.DecodeString(k.N)
	if err != nil {
		return nil, err
	}
	eb, err := base64.RawURLEncoding.DecodeString(k.E)
	if err != nil {
		return nil, err
	}
	e := 0
	for _, b := range eb {
		e = e<<8 | int(b)
	}
	return &rsa.PublicKey{N: new(big.Int).SetBytes(nb), E: e}, nil
}

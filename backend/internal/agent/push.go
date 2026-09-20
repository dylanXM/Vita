package agent

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const firebaseMessagingScope = "https://www.googleapis.com/auth/firebase.messaging"

type firebaseServiceAccount struct {
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
}

type FCMClient struct {
	projectID    string
	account      firebaseServiceAccount
	privateKey   *rsa.PrivateKey
	httpClient   *http.Client
	endpointBase string

	mu          sync.Mutex
	accessToken string
	tokenExpiry time.Time
}

type PushMessage struct {
	Token string
	Title string
	Body  string
	Data  map[string]string
}

type FCMError struct {
	StatusCode   int
	Body         string
	Unregistered bool
}

func (e *FCMError) Error() string {
	return fmt.Sprintf("fcm returned status %d: %s", e.StatusCode, e.Body)
}

// NewFCMClient returns nil when push is intentionally not configured. The
// preferred input is base64-encoded service-account JSON; raw JSON remains
// accepted for compatibility with the project's earlier environment name.
func NewFCMClient(projectID, serviceAccountBase64 string) (*FCMClient, error) {
	projectID = strings.TrimSpace(projectID)
	serviceAccountBase64 = strings.TrimSpace(serviceAccountBase64)
	if projectID == "" && serviceAccountBase64 == "" {
		return nil, nil
	}
	if serviceAccountBase64 == "" {
		return nil, errors.New("VITA_FIREBASE_SERVICE_ACCOUNT_BASE64 is required when Firebase push is enabled")
	}
	raw := []byte(serviceAccountBase64)
	if !strings.HasPrefix(serviceAccountBase64, "{") {
		decoded, err := base64.StdEncoding.DecodeString(serviceAccountBase64)
		if err != nil {
			return nil, fmt.Errorf("decode Firebase service account: %w", err)
		}
		raw = decoded
	}
	var account firebaseServiceAccount
	if err := json.Unmarshal(raw, &account); err != nil {
		return nil, fmt.Errorf("parse Firebase service account: %w", err)
	}
	if account.ClientEmail == "" || account.PrivateKey == "" {
		return nil, errors.New("Firebase service account is missing client_email or private_key")
	}
	if account.TokenURI == "" {
		account.TokenURI = "https://oauth2.googleapis.com/token"
	}
	if projectID == "" {
		projectID = account.ProjectID
	}
	if projectID == "" {
		return nil, errors.New("Firebase project id is missing")
	}
	block, _ := pem.Decode([]byte(account.PrivateKey))
	if block == nil {
		return nil, errors.New("Firebase service account private_key is not valid PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse Firebase private key: %w", err)
	}
	privateKey, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("Firebase private key is not RSA")
	}
	return &FCMClient{
		projectID: projectID, account: account, privateKey: privateKey,
		httpClient: &http.Client{Timeout: 15 * time.Second}, endpointBase: "https://fcm.googleapis.com",
	}, nil
}

func (c *FCMClient) Send(ctx context.Context, message PushMessage) error {
	accessToken, err := c.token(ctx)
	if err != nil {
		return err
	}
	body := map[string]any{"message": map[string]any{
		"token":        message.Token,
		"notification": map[string]string{"title": message.Title, "body": message.Body},
		"data":         message.Data,
		"android": map[string]any{
			"priority":     "high",
			"notification": map[string]string{"sound": "default"},
		},
		"apns": map[string]any{
			"headers": map[string]string{"apns-priority": "10"},
			"payload": map[string]any{"aps": map[string]any{"sound": "default"}},
		},
	}}
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}
	endpoint := strings.TrimRight(c.endpointBase, "/") + "/v1/projects/" + url.PathEscape(c.projectID) + "/messages:send"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(encoded))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send FCM request: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		bodyText := strings.TrimSpace(string(raw))
		return &FCMError{
			StatusCode:   resp.StatusCode,
			Body:         truncate(bodyText, 1000),
			Unregistered: strings.Contains(bodyText, "UNREGISTERED"),
		}
	}
	return nil
}

func (c *FCMClient) token(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.accessToken != "" && time.Now().Add(5*time.Minute).Before(c.tokenExpiry) {
		return c.accessToken, nil
	}
	now := time.Now()
	header, _ := json.Marshal(map[string]string{"alg": "RS256", "typ": "JWT"})
	claims, _ := json.Marshal(map[string]any{
		"iss":   c.account.ClientEmail,
		"scope": firebaseMessagingScope,
		"aud":   c.account.TokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	})
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(claims)
	digest := sha256.Sum256([]byte(unsigned))
	signature, err := rsa.SignPKCS1v15(rand.Reader, c.privateKey, crypto.SHA256, digest[:])
	if err != nil {
		return "", fmt.Errorf("sign Firebase assertion: %w", err)
	}
	assertion := unsigned + "." + base64.RawURLEncoding.EncodeToString(signature)
	form := url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {assertion},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.account.TokenURI, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("request Firebase access token: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("Firebase OAuth returned %s: %s", resp.Status, truncate(strings.TrimSpace(string(raw)), 1000))
	}
	var output struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   any    `json:"expires_in"`
	}
	if err := json.Unmarshal(raw, &output); err != nil {
		return "", fmt.Errorf("decode Firebase access token: %w", err)
	}
	if output.AccessToken == "" {
		return "", errors.New("Firebase OAuth response did not contain access_token")
	}
	expiresIn := int64(3600)
	switch value := output.ExpiresIn.(type) {
	case float64:
		expiresIn = int64(value)
	case string:
		if parsed, parseErr := strconv.ParseInt(value, 10, 64); parseErr == nil {
			expiresIn = parsed
		}
	}
	c.accessToken = output.AccessToken
	c.tokenExpiry = now.Add(time.Duration(expiresIn) * time.Second)
	return c.accessToken, nil
}

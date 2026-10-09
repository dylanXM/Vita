package handler

import (
	"context"
	"crypto/ecdsa"
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

const admobKeyURL = "https://www.gstatic.com/admob/reward/verifier-keys.json"

var admobKeys struct {
	sync.Mutex
	values  map[int]*ecdsa.PublicKey
	expires time.Time
}

func verifyAdmobCallback(ctx context.Context, rawQuery string) error {
	if len(rawQuery) > 8192 {
		return errors.New("callback query too long")
	}
	separator := strings.LastIndex(rawQuery, "&signature=")
	if separator <= 0 {
		return errors.New("missing signature")
	}
	signed := rawQuery[:separator]
	tail := rawQuery[separator+len("&signature="):]
	parts := strings.Split(tail, "&key_id=")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" || strings.Contains(parts[1], "&") {
		return errors.New("invalid signature parameters")
	}
	signatureText, err := url.QueryUnescape(parts[0])
	if err != nil {
		return err
	}
	signature, err := base64.RawURLEncoding.DecodeString(signatureText)
	if err != nil {
		signature, err = base64.URLEncoding.DecodeString(signatureText)
		if err != nil {
			return err
		}
	}
	keyID, err := strconv.Atoi(parts[1])
	if err != nil {
		return err
	}
	key, err := admobPublicKey(ctx, keyID)
	if err != nil {
		return err
	}
	hash := sha256.Sum256([]byte(signed))
	if !ecdsa.VerifyASN1(key, hash[:], signature) {
		return errors.New("invalid callback signature")
	}
	return nil
}

func admobPublicKey(ctx context.Context, keyID int) (*ecdsa.PublicKey, error) {
	admobKeys.Lock()
	defer admobKeys.Unlock()
	if time.Now().Before(admobKeys.expires) {
		if key := admobKeys.values[keyID]; key != nil {
			return key, nil
		}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, admobKeyURL, nil)
	if err != nil {
		return nil, err
	}
	client := &http.Client{Timeout: 4 * time.Second}
	response, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("AdMob keys returned %d", response.StatusCode)
	}
	var document struct {
		Keys []struct {
			ID  int    `json:"keyId"`
			PEM string `json:"pem"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&document); err != nil {
		return nil, err
	}
	keys := make(map[int]*ecdsa.PublicKey, len(document.Keys))
	for _, item := range document.Keys {
		block, _ := pem.Decode([]byte(item.PEM))
		if block == nil {
			return nil, errors.New("invalid AdMob public key")
		}
		parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
		if err != nil {
			return nil, err
		}
		key, ok := parsed.(*ecdsa.PublicKey)
		if !ok {
			return nil, errors.New("unexpected AdMob public key type")
		}
		keys[item.ID] = key
	}
	if len(keys) == 0 {
		return nil, errors.New("no AdMob public keys")
	}
	admobKeys.values = keys
	admobKeys.expires = time.Now().Add(12 * time.Hour)
	key := keys[keyID]
	if key == nil {
		return nil, errors.New("unknown AdMob key ID")
	}
	return key, nil
}

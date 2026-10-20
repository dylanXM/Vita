package agent

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestFCMSendUsesOAuthAndNotificationPayload(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	encodedKey, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/token":
			if err := r.ParseForm(); err != nil || r.Form.Get("assertion") == "" {
				t.Errorf("missing OAuth assertion: %v", err)
			}
			_, _ = io.WriteString(w, `{"access_token":"test-access","expires_in":3600}`)
		case "/v1/projects/test-project/messages:send":
			if r.Header.Get("Authorization") != "Bearer test-access" {
				t.Errorf("authorization = %q", r.Header.Get("Authorization"))
			}
			var body map[string]any
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Error(err)
			}
			message, _ := body["message"].(map[string]any)
			if message["token"] != "device-token" {
				t.Errorf("message = %#v", message)
			}
			_, _ = io.WriteString(w, `{"name":"projects/test/messages/1"}`)
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	account := firebaseServiceAccount{
		ProjectID: "test-project", ClientEmail: "push@test-project.iam.gserviceaccount.com",
		PrivateKey: string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: encodedKey})),
		TokenURI:   server.URL + "/token",
	}
	raw, _ := json.Marshal(account)
	client, err := NewFCMClient("test-project", base64.StdEncoding.EncodeToString(raw))
	if err != nil {
		t.Fatal(err)
	}
	client.endpointBase = server.URL
	if err := client.Send(context.Background(), PushMessage{
		Token: "device-token", Title: "Mia", Body: "刚下班", Data: map[string]string{"route": "companion_chat"},
	}); err != nil {
		t.Fatal(err)
	}
}

func TestFCMUnregisteredTokenIsClassified(t *testing.T) {
	client := &FCMClient{
		projectID: "test", accessToken: "token",
		tokenExpiry: time.Now().AddDate(1, 0, 0),
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		_, _ = io.WriteString(w, `{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}`)
	}))
	defer server.Close()
	client.httpClient = server.Client()
	client.endpointBase = server.URL
	err := client.Send(context.Background(), PushMessage{Token: "expired", Title: "Vita", Body: "hello"})
	var fcmErr *FCMError
	if !errors.As(err, &fcmErr) || !fcmErr.Unregistered || !strings.Contains(fcmErr.Body, "UNREGISTERED") {
		t.Fatalf("error = %#v", err)
	}
}

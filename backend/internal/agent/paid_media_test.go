package agent

import (
	"context"
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPaidImageRequiresUsableContent(t *testing.T) {
	png, _ := base64.StdEncoding.DecodeString("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6rKsAAAAASUVORK5CYII=")
	for _, tc := range []struct {
		name   string
		status int
		body   []byte
		ok     bool
	}{
		{"image", 200, png, true}, {"missing", 404, png, false}, {"provider error", 200, []byte(`{"error":"failed"}`), false}, {"empty", 200, nil, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(tc.status); _, _ = w.Write(tc.body) }))
			defer server.Close()
			data, mime, err := NewClient().downloadPaidImage(context.Background(), server.URL)
			if tc.ok {
				if err != nil || len(data) == 0 || mime != "image/png" {
					t.Fatalf("mime=%s err=%v", mime, err)
				}
			} else if err == nil {
				t.Fatal("unusable photo accepted")
			}
		})
	}
	data, mime, err := NewClient().downloadPaidImage(context.Background(), "data:image/png;base64,"+base64.StdEncoding.EncodeToString(png))
	if err != nil || len(data) != len(png) || mime != "image/png" {
		t.Fatalf("data image err=%v", err)
	}
}

func TestPaidSpeechRejectsProviderErrorBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "audio/mpeg")
		_, _ = w.Write([]byte(`{"error":"generation failed"}`))
	}))
	defer server.Close()
	_, _, err := NewClient().GenerateSpeech(context.Background(), Model{Kind: "openai", BaseURL: server.URL, ModelName: "test"}, "Hello", "alloy")
	if err == nil {
		t.Fatal("provider error body treated as speech")
	}
}

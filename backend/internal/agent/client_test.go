package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestOpenAICompatibleClient(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("path = %s", r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer key" {
			t.Fatal("missing authorization")
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{"message": map[string]any{"role": "assistant", "content": " hello "}}},
		})
	}))
	defer server.Close()

	client := NewClient()
	text, err := client.GenerateText(context.Background(), Model{
		Kind: "openai", BaseURL: server.URL, APIKey: "key", ModelName: "model",
	}, GenerateRequest{System: "system", Messages: []ChatMessage{{Role: "user", Content: "hi"}}, MaxTokens: 20})
	if err != nil {
		t.Fatal(err)
	}
	if text != "hello" {
		t.Fatalf("text = %q", text)
	}
}

func TestAnthropicClient(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" || r.Header.Get("x-api-key") != "key" {
			t.Fatal("unexpected anthropic request")
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"content": []any{map[string]any{"type": "text", "text": "hello"}},
		})
	}))
	defer server.Close()

	client := NewClient()
	text, err := client.GenerateText(context.Background(), Model{
		Kind: "anthropic", BaseURL: server.URL, APIKey: "key", ModelName: "model",
	}, GenerateRequest{Messages: []ChatMessage{{Role: "user", Content: "hi"}}, MaxTokens: 20})
	if err != nil {
		t.Fatal(err)
	}
	if text != "hello" {
		t.Fatalf("text = %q", text)
	}
}

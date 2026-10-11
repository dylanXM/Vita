package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestOpenAICompatibleImageClient(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/images/generations" {
			t.Fatalf("path = %s", r.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"data": []any{map[string]any{"url": "https://cdn.example/life.png"}}})
	}))
	defer server.Close()

	url, err := NewClient().GenerateImage(context.Background(), Model{Kind: "openai", BaseURL: server.URL, APIKey: "key", ModelName: "image-model"}, GenerateImageRequest{Prompt: "ordinary cafe"})
	if err != nil {
		t.Fatal(err)
	}
	if url != "https://cdn.example/life.png" {
		t.Fatalf("url = %q", url)
	}
}

func TestOpenAICompatibleAudioClient(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/audio/transcriptions":
			if err := r.ParseMultipartForm(1 << 20); err != nil {
				t.Fatal(err)
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"text": "voice transcript"})
		case "/v1/audio/speech":
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write([]byte("mp3-data"))
		default:
			t.Fatalf("path = %s", r.URL.Path)
		}
	}))
	defer server.Close()
	client := NewClient()
	model := Model{Kind: "openai", BaseURL: server.URL, APIKey: "key", ModelName: "audio-model"}
	transcript, err := client.TranscribeAudio(context.Background(), model, "voice.m4a", "audio/mp4", []byte("audio"))
	if err != nil || transcript != "voice transcript" {
		t.Fatalf("transcript = %q, err = %v", transcript, err)
	}
	audio, mimeType, err := client.GenerateSpeech(context.Background(), model, "hello", "alloy")
	if err != nil || string(audio) != "mp3-data" || mimeType != "audio/mpeg" {
		t.Fatalf("audio = %q, mime = %q, err = %v", audio, mimeType, err)
	}
}

func TestKieImageClient(t *testing.T) {
	var createBody map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/v1/jobs/createTask":
			_ = json.NewDecoder(r.Body).Decode(&createBody)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"code": 200, "msg": "success",
				"data": map[string]any{"taskId": "task_abc"},
			})
		case "/api/v1/jobs/recordInfo":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"code": 200, "msg": "success",
				"data": map[string]any{
					"state":      "success",
					"resultJson": `{"resultUrls":["https://cdn.example/kie-life.png"]}`,
				},
			})
		default:
			t.Fatalf("path = %s", r.URL.Path)
		}
	}))
	defer server.Close()

	url, err := NewClient().GenerateImage(context.Background(), Model{
		Kind: "kie", BaseURL: server.URL, APIKey: "key", ModelName: "grok-imagine/text-to-image",
	}, GenerateImageRequest{Prompt: "ordinary cafe"})
	if err != nil {
		t.Fatal(err)
	}
	if url != "https://cdn.example/kie-life.png" {
		t.Fatalf("url = %q", url)
	}
	if createBody["model"] != "grok-imagine/text-to-image" {
		t.Fatalf("model in body = %v", createBody["model"])
	}
}

func TestKieSpeechClient(t *testing.T) {
	var resultJSON string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/v1/jobs/createTask":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"code": 200, "msg": "success",
				"data": map[string]any{"taskId": "task_voice"},
			})
		case "/api/v1/jobs/recordInfo":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"code": 200, "msg": "success",
				"data": map[string]any{
					"state":      "success",
					"resultJson": resultJSON,
				},
			})
		case "/kie-voice.mp3":
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write([]byte("kie-mp3"))
		default:
			t.Fatalf("path = %s", r.URL.Path)
		}
	}))
	defer server.Close()
	resultJSON = `{"resultUrls":["` + server.URL + `/kie-voice.mp3"]}`

	audio, mimeType, err := NewClient().GenerateSpeech(context.Background(), Model{
		Kind: "kie", BaseURL: server.URL, APIKey: "key", ModelName: "elevenlabs/tts",
	}, "hello", "alloy")
	if err != nil {
		t.Fatal(err)
	}
	if string(audio) != "kie-mp3" || mimeType != "audio/mpeg" {
		t.Fatalf("audio = %q, mime = %q", string(audio), mimeType)
	}
}

func TestKieTestConnection(t *testing.T) {
	// Valid key: recordInfo probe returns 404 (task not found) but HTTP 200-ish.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/jobs/recordInfo" {
			t.Fatalf("path = %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"code": 404, "msg": "task not found"})
	}))
	defer server.Close()
	_, raw, err := NewClient().TestConnection(context.Background(), Model{
		Kind: "kie", BaseURL: server.URL, APIKey: "key", ModelName: "x",
	})
	if err != nil {
		t.Fatalf("expected valid key, got %v (raw=%s)", err, raw)
	}

	// Invalid key: 401.
	authServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte("unauthorized"))
	}))
	defer authServer.Close()
	_, _, err = NewClient().TestConnection(context.Background(), Model{
		Kind: "kie", BaseURL: authServer.URL, APIKey: "bad", ModelName: "x",
	})
	if err == nil {
		t.Fatal("expected auth error for bad key")
	}
}

// TestAnthropicKindOpenAIResponse guards against proxies that answer an
// anthropic-shaped /messages request with an OpenAI-compatible body
// (choices[].message.content). anthropic() must extract text from both shapes.
func TestAnthropicKindOpenAIResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" || r.Header.Get("x-api-key") != "key" {
			t.Fatal("unexpected anthropic request")
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{"message": map[string]any{"role": "assistant", "content": `[{"type":"meal","title":"Lunch","description":"Ramen at the corner shop.","location":"cafe","start":"12:00","end":"12:40","emotion":"happy","importance":30,"user_relevance":20,"share":false,"moment":false,"moment_text":"","media_urls":[]}]`}}},
		})
	}))
	defer server.Close()

	client := NewClient()
	text, err := client.GenerateText(context.Background(), Model{
		Kind: "anthropic", BaseURL: server.URL, APIKey: "key", ModelName: "model",
	}, GenerateRequest{Messages: []ChatMessage{{Role: "user", Content: "hi"}}, MaxTokens: 4096})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(strings.TrimSpace(text), "[") {
		t.Fatalf("expected JSON array text, got %q", text)
	}
}

// TestAnthropicNoTextDiagnostics verifies the failure path now reports the
// actual content blocks and a raw response snippet instead of a bare message.
func TestAnthropicNoTextDiagnostics(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"content": []any{map[string]any{"type": "thinking", "thinking": "let me think"}},
		})
	}))
	defer server.Close()

	client := NewClient()
	_, err := client.GenerateText(context.Background(), Model{
		Kind: "anthropic", BaseURL: server.URL, APIKey: "key", ModelName: "model",
	}, GenerateRequest{Messages: []ChatMessage{{Role: "user", Content: "hi"}}, MaxTokens: 4096})
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "content blocks: thinking") {
		t.Fatalf("expected block diagnostics, got %v", err)
	}
	if !strings.Contains(err.Error(), "raw:") {
		t.Fatalf("expected raw snippet, got %v", err)
	}
}

func TestClientRejectsTokenTruncatedText(t *testing.T) {
	for _, kind := range []string{"openai", "anthropic"} {
		t.Run(kind, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if kind == "openai" {
					w.Write([]byte(`{"choices":[{"finish_reason":"length","message":{"content":"小组作业的初"}}]}`))
				} else {
					w.Write([]byte(`{"stop_reason":"max_tokens","content":[{"type":"text","text":"小组作业的初"}]}`))
				}
			}))
			defer server.Close()
			text, err := NewClient().GenerateText(context.Background(), Model{Kind: kind, BaseURL: server.URL, APIKey: "key", ModelName: "test"}, GenerateRequest{MaxTokens: 10})
			if err == nil || text != "" {
				t.Fatalf("truncated reply accepted: %q, %v", text, err)
			}
		})
	}
}

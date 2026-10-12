package agent

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
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
	// Valid key: authenticated credit API, including zero balance.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/chat/credit" {
			t.Fatalf("path = %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"code": 200, "msg": "success", "data": 0})
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

func TestKieConnectionBusinessError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"code": 401, "msg": "invalid API key"})
	}))
	defer server.Close()
	_, _, err := NewClient().TestConnection(context.Background(), Model{Kind: "kie", BaseURL: server.URL + "/api/v1", APIKey: "bad"})
	if err == nil {
		t.Fatal("HTTP 200 business error was accepted")
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

func TestKieSunburstImageClient(t *testing.T) {
	t.Setenv("VITA_PUBLIC_API_BASE_URL", "https://api.example.com")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Header.Get("Authorization") != "Bearer key" {
			t.Error("missing authorization")
		}
		switch r.URL.Path {
		case "/api/v1/jobs/createTask":
			var body struct {
				Model    string            `json:"model"`
				Input    map[string]string `json:"input"`
				Callback string            `json:"callBackUrl"`
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			if body.Callback != "https://api.example.com/v1/providers/kie/callback" {
				t.Errorf("callback=%q", body.Callback)
			}
			if body.Model != "gpt-image-2-5-sunburst-text-to-image" || body.Input["prompt"] != "cafe" || body.Input["aspect_ratio"] != "1:1" || body.Input["resolution"] != "1K" || body.Input["background"] != "opaque" {
				t.Errorf("unexpected request: %+v", body)
			}
			io.WriteString(w, `{"code":200,"data":{"taskId":"task+1"}}`)
		case "/api/v1/jobs/recordInfo":
			if r.URL.Query().Get("taskId") != "task+1" {
				t.Error("task ID was not escaped")
			}
			io.WriteString(w, `{"code":200,"data":{"state":"success","resultJson":"{\"resultUrls\":[\"https://cdn.example/image.png\"]}"}}`)
		default:
			t.Errorf("unexpected path %s", r.URL.Path)
		}
	}))
	defer server.Close()
	result, err := NewClient().GenerateImage(context.Background(), Model{Kind: "kie", BaseURL: server.URL, APIKey: "key", ModelName: "gpt-image-2-5-sunburst-text-to-image"}, GenerateImageRequest{Prompt: "cafe", Size: "1024x1024"})
	if err != nil || result != "https://cdn.example/image.png" {
		t.Fatalf("result=%q err=%v", result, err)
	}
}

func TestKiePollRejectsProviderError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, `{"code":401,"msg":"unauthorized","data":{"state":"success","resultJson":"invalid"}}`)
	}))
	defer server.Close()
	if _, err := NewClient().kiePollResult(context.Background(), Model{BaseURL: server.URL}, "task"); err == nil {
		t.Fatal("provider error accepted")
	}
}

func TestKieBaseAcceptsTaskEndpoint(t *testing.T) {
	for _, base := range []string{"https://api.kie.ai", "https://api.kie.ai/api/v1/jobs/createTask/", "https://api.kie.ai/api/v1"} {
		if actual := kieBase(Model{BaseURL: base}); actual != "https://api.kie.ai" {
			t.Errorf("base=%s actual=%s", base, actual)
		}
	}
}
func TestKieCallbackSignalsOnlyPendingTask(t *testing.T) {
	ch := make(chan struct{}, 1)
	kiePendingTasks.Store("pending", ch)
	defer kiePendingTasks.Delete("pending")
	NotifyKieTask("unknown")
	NotifyKieTask("pending")
	NotifyKieTask("pending")
	select {
	case <-ch:
	default:
		t.Fatal("missing callback notification")
	}
}

func TestLifePlanTimeoutIsRequestScoped(t *testing.T) {
	client := NewClient()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := client.GenerateText(ctx, Model{Kind: "openai", BaseURL: "http://127.0.0.1:1", ModelName: "test"}, GenerateRequest{MaxTokens: 10, Timeout: lifePlanRequestTimeout})
	if err == nil {
		t.Fatal("request deadline ignored caller cancellation")
	}
	if client.httpClient.Timeout != 45*time.Second {
		t.Fatal("life plan changed shared chat client timeout")
	}
}

func TestLifePlanTokenLimitRecovery(t *testing.T) {
	for _, kind := range []string{"openai", "anthropic"} {
		t.Run(kind, func(t *testing.T) {
			calls := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls++
				var body struct {
					MaxTokens int `json:"max_tokens"`
				}
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatal(err)
				}
				expected := 8192
				if calls == 2 {
					expected = 16384
				}
				if body.MaxTokens != expected {
					t.Errorf("budget=%d want=%d", body.MaxTokens, expected)
				}
				// Some Anthropic gateways also return the OpenAI response shape.
				if calls == 1 {
					_, _ = w.Write([]byte(`{"choices":[{"finish_reason":"length","message":{"content":"[{"}}]}`))
					return
				}
				_, _ = w.Write([]byte(`{"choices":[{"finish_reason":"stop","message":{"content":"[]"}}]}`))
			}))
			defer server.Close()
			text, err := NewClient().generateLifePlanText(context.Background(), Model{Kind: kind, BaseURL: server.URL, ModelName: "test"}, GenerateRequest{MaxTokens: 8192})
			if err != nil || text != "[]" || calls != 2 {
				t.Fatalf("text=%q err=%v calls=%d", text, err, calls)
			}
		})
	}
}

func TestLifePlanDoesNotRetryHTTPFailure(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	}))
	defer server.Close()
	_, err := NewClient().generateLifePlanText(context.Background(), Model{Kind: "openai", BaseURL: server.URL, ModelName: "test"}, GenerateRequest{MaxTokens: 8192})
	if err == nil || calls != 1 {
		t.Fatalf("err=%v calls=%d", err, calls)
	}
}

func TestLifePlanTokenLimitRetryIsBounded(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		_, _ = w.Write([]byte(`{"stop_reason":"max_tokens","content":[{"type":"text","text":"[{"}]}`))
	}))
	defer server.Close()
	text, err := NewClient().generateLifePlanText(context.Background(), Model{Kind: "anthropic", BaseURL: server.URL, ModelName: "test"}, GenerateRequest{MaxTokens: 8192})
	if err != errTextTokenLimit || text != "" || calls != 2 {
		t.Fatalf("text=%q err=%v calls=%d", text, err, calls)
	}
}

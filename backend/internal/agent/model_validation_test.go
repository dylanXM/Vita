package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestModelScenarioCallsTheSelectedRuntimeEndpoint(t *testing.T) {
	tests := map[string]string{
		"text_chat":              "/v1/chat/completions",
		"text_life_plan":         "/v1/chat/completions",
		"text_proactive":         "/v1/chat/completions",
		"text_story_chapter":     "/v1/chat/completions",
		"text_storyboard":        "/v1/chat/completions",
		"image_life_photo":       "/v1/images/generations",
		"image_requested_photo":  "/v1/images/generations",
		"image_storyboard_sheet": "/v1/images/generations",
		"audio_speech":           "/v1/audio/speech",
		"audio_transcription":    "/v1/audio/transcriptions",
	}
	for scenario, expectedPath := range tests {
		t.Run(scenario, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != expectedPath {
					t.Fatalf("path = %s, want %s", r.URL.Path, expectedPath)
				}
				switch expectedPath {
				case "/v1/chat/completions":
					content := "ok"
					if scenario == "text_life_plan" {
						content = `[{"type":"routine","title":"Lunch","description":"Makes lunch at home","location":"home","start":"12:00","end":"12:30","emotion":"calm","importance":40,"user_relevance":10,"share":false,"moment":false,"moment_text":"","media_urls":[]}]`
					}
					_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": content}}}})
				case "/v1/images/generations":
					_ = json.NewEncoder(w).Encode(map[string]any{"data": []any{map[string]any{"url": "https://example.com/test.png"}}})
				case "/v1/audio/speech":
					_, _ = w.Write([]byte("audio"))
				case "/v1/audio/transcriptions":
					_ = json.NewEncoder(w).Encode(map[string]any{"text": "test"})
				}
			}))
			defer server.Close()
			model := Model{Kind: "openai", BaseURL: server.URL, APIKey: "key", ModelName: "model"}
			audio := &ModelTestAudio{Filename: "test.m4a", MIMEType: "audio/mp4", Data: []byte("audio")}
			if err := TestModelScenario(context.Background(), NewClient(), model, scenario, audio); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestModelScenarioRejectsMissingAdapterAndAudio(t *testing.T) {
	model := Model{Kind: "openai", ModelName: "model"}
	if err := TestModelScenario(context.Background(), NewClient(), model, "video_life_clip", nil); err == nil {
		t.Fatal("expected video scenario to be rejected")
	}
	if err := TestModelScenario(context.Background(), NewClient(), model, "audio_transcription", nil); err == nil {
		t.Fatal("expected missing transcription audio to be rejected")
	}
}

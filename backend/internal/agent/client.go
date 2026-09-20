package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"time"
)

const maxProviderResponseBytes = 4 << 20
const maxImageProviderResponseBytes = 16 << 20

type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type Model struct {
	ID        string
	Kind      string
	BaseURL   string
	APIKey    string
	ModelName string
}

type GenerateRequest struct {
	System      string
	Messages    []ChatMessage
	Temperature float64
	MaxTokens   int
}

type GenerateImageRequest struct {
	Prompt string
	Size   string
}

func (c *Client) TranscribeAudio(ctx context.Context, model Model, filename, mimeType string, audio []byte) (string, error) {
	if model.Kind != "openai" {
		return "", fmt.Errorf("audio transcription is unsupported for provider kind %q", model.Kind)
	}
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	_ = writer.WriteField("model", model.ModelName)
	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		return "", err
	}
	if _, err := part.Write(audio); err != nil {
		return "", err
	}
	if err := writer.Close(); err != nil {
		return "", err
	}
	endpoint := strings.TrimRight(defaultBaseURL(model.Kind, model.BaseURL), "/") + "/v1/audio/transcriptions"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, &body)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+model.APIKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("provider request: %w", err)
	}
	defer resp.Body.Close()
	reader := io.LimitReader(resp.Body, maxProviderResponseBytes)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(reader)
		return "", fmt.Errorf("provider returned %s: %s", resp.Status, strings.TrimSpace(string(raw)))
	}
	var output struct {
		Text string `json:"text"`
	}
	if err := json.NewDecoder(reader).Decode(&output); err != nil {
		return "", fmt.Errorf("decode transcription response: %w", err)
	}
	if strings.TrimSpace(output.Text) == "" {
		return "", fmt.Errorf("provider returned an empty transcription")
	}
	return strings.TrimSpace(output.Text), nil
}

func (c *Client) GenerateSpeech(ctx context.Context, model Model, text, voice string) ([]byte, string, error) {
	if model.Kind != "openai" {
		return nil, "", fmt.Errorf("speech generation is unsupported for provider kind %q", model.Kind)
	}
	if strings.TrimSpace(voice) == "" {
		voice = "alloy"
	}
	body, _ := json.Marshal(map[string]any{"model": model.ModelName, "voice": voice, "input": text, "response_format": "mp3"})
	endpoint := strings.TrimRight(defaultBaseURL(model.Kind, model.BaseURL), "/") + "/v1/audio/speech"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, "", err
	}
	req.Header.Set("Authorization", "Bearer "+model.APIKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, "", fmt.Errorf("provider request: %w", err)
	}
	defer resp.Body.Close()
	reader := io.LimitReader(resp.Body, 10<<20)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(reader)
		return nil, "", fmt.Errorf("provider returned %s: %s", resp.Status, strings.TrimSpace(string(raw)))
	}
	audio, err := io.ReadAll(reader)
	if err != nil || len(audio) == 0 {
		return nil, "", fmt.Errorf("provider returned empty speech audio")
	}
	mimeType := resp.Header.Get("Content-Type")
	if mimeType == "" {
		mimeType = "audio/mpeg"
	}
	return audio, mimeType, nil
}

type Client struct {
	httpClient *http.Client
}

func NewClient() *Client {
	return &Client{httpClient: &http.Client{Timeout: 45 * time.Second}}
}

func (c *Client) GenerateText(ctx context.Context, model Model, input GenerateRequest) (string, error) {
	switch model.Kind {
	case "openai":
		return c.openAI(ctx, model, input)
	case "anthropic":
		return c.anthropic(ctx, model, input)
	default:
		return "", fmt.Errorf("unsupported provider kind %q", model.Kind)
	}
}

func (c *Client) GenerateImage(ctx context.Context, model Model, input GenerateImageRequest) (string, error) {
	if model.Kind != "openai" {
		return "", fmt.Errorf("image generation is unsupported for provider kind %q", model.Kind)
	}
	size := strings.TrimSpace(input.Size)
	if size == "" {
		size = "1024x1024"
	}
	body := map[string]any{"model": model.ModelName, "prompt": input.Prompt, "size": size, "n": 1}
	var response struct {
		Data []struct {
			URL     string `json:"url"`
			B64JSON string `json:"b64_json"`
		} `json:"data"`
	}
	endpoint := strings.TrimRight(defaultBaseURL(model.Kind, model.BaseURL), "/") + "/v1/images/generations"
	if err := c.doJSONWithLimit(ctx, endpoint, model.APIKey, "", body, &response, maxImageProviderResponseBytes); err != nil {
		return "", err
	}
	if len(response.Data) == 0 {
		return "", fmt.Errorf("openai-compatible provider returned no image")
	}
	if imageURL := strings.TrimSpace(response.Data[0].URL); imageURL != "" {
		return imageURL, nil
	}
	if encoded := strings.TrimSpace(response.Data[0].B64JSON); encoded != "" {
		return "data:image/png;base64," + encoded, nil
	}
	return "", fmt.Errorf("openai-compatible provider returned an empty image")
}

func (c *Client) openAI(ctx context.Context, model Model, input GenerateRequest) (string, error) {
	messages := make([]ChatMessage, 0, len(input.Messages)+1)
	if input.System != "" {
		messages = append(messages, ChatMessage{Role: "system", Content: input.System})
	}
	messages = append(messages, input.Messages...)
	body := map[string]any{
		"model":       model.ModelName,
		"messages":    messages,
		"temperature": input.Temperature,
		"max_tokens":  input.MaxTokens,
	}
	var response struct {
		Choices []struct {
			Message ChatMessage `json:"message"`
		} `json:"choices"`
	}
	endpoint := strings.TrimRight(defaultBaseURL(model.Kind, model.BaseURL), "/") + "/v1/chat/completions"
	if err := c.doJSON(ctx, endpoint, model.APIKey, "", body, &response); err != nil {
		return "", err
	}
	if len(response.Choices) == 0 || strings.TrimSpace(response.Choices[0].Message.Content) == "" {
		return "", fmt.Errorf("openai-compatible provider returned no text")
	}
	return strings.TrimSpace(response.Choices[0].Message.Content), nil
}

func (c *Client) anthropic(ctx context.Context, model Model, input GenerateRequest) (string, error) {
	body := map[string]any{
		"model":       model.ModelName,
		"system":      input.System,
		"messages":    input.Messages,
		"temperature": input.Temperature,
		"max_tokens":  input.MaxTokens,
	}
	var response struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	endpoint := strings.TrimRight(defaultBaseURL(model.Kind, model.BaseURL), "/") + "/v1/messages"
	if err := c.doJSON(ctx, endpoint, model.APIKey, "2023-06-01", body, &response); err != nil {
		return "", err
	}
	for _, block := range response.Content {
		if block.Type == "text" && strings.TrimSpace(block.Text) != "" {
			return strings.TrimSpace(block.Text), nil
		}
	}
	return "", fmt.Errorf("anthropic provider returned no text")
}

func (c *Client) doJSON(ctx context.Context, endpoint, apiKey, anthropicVersion string, body any, output any) error {
	return c.doJSONWithLimit(ctx, endpoint, apiKey, anthropicVersion, body, output, maxProviderResponseBytes)
}

func (c *Client) doJSONWithLimit(ctx context.Context, endpoint, apiKey, anthropicVersion string, body any, output any, responseLimit int64) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("encode provider request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(encoded))
	if err != nil {
		return fmt.Errorf("create provider request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if anthropicVersion != "" {
		req.Header.Set("x-api-key", apiKey)
		req.Header.Set("anthropic-version", anthropicVersion)
	} else {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("provider request: %w", err)
	}
	defer resp.Body.Close()
	reader := io.LimitReader(resp.Body, responseLimit)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(reader)
		return fmt.Errorf("provider returned %s: %s", resp.Status, strings.TrimSpace(string(raw)))
	}
	if err := json.NewDecoder(reader).Decode(output); err != nil {
		return fmt.Errorf("decode provider response: %w", err)
	}
	return nil
}

func defaultBaseURL(kind, configured string) string {
	if strings.TrimSpace(configured) != "" {
		return strings.TrimSpace(configured)
	}
	if kind == "anthropic" {
		return "https://api.anthropic.com"
	}
	return "https://api.openai.com"
}

package agent

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Rates are USD per million tokens, or USD per successful media call.
// Nil means unconfigured; zero is an explicitly free rate.
type ModelRates struct {
	Unit       string   `json:"unit"`
	Input      *float64 `json:"input"`
	Output     *float64 `json:"output"`
	CacheRead  *float64 `json:"cache_read"`
	CacheWrite *float64 `json:"cache_write"`
	Call       *float64 `json:"call"`
}
type callTraceKey struct{}
type callTrace struct {
	started                              time.Time
	rates                                ModelRates
	input, output, cacheRead, cacheWrite int64
	usage                                bool
}

func NewMeteredClient(db *sql.DB) *Client {
	c := NewClient()
	c.recorder = db
	return c
}
func (t *callTrace) readUsage(raw []byte) {
	var r struct {
		Usage *struct {
			Prompt     *int64 `json:"prompt_tokens"`
			Completion *int64 `json:"completion_tokens"`
			Input      *int64 `json:"input_tokens"`
			Output     *int64 `json:"output_tokens"`
			CacheRead  int64  `json:"cache_read_input_tokens"`
			CacheWrite int64  `json:"cache_creation_input_tokens"`
			Details    struct {
				Cached int64 `json:"cached_tokens"`
			} `json:"prompt_tokens_details"`
		} `json:"usage"`
	}
	if json.Unmarshal(raw, &r) != nil || r.Usage == nil {
		return
	}
	u := r.Usage
	if u.Prompt != nil && u.Completion != nil {
		t.input = *u.Prompt - u.Details.Cached
		t.output = *u.Completion
		t.cacheRead = u.Details.Cached
		t.usage = true
	} else if u.Input != nil && u.Output != nil {
		t.input = *u.Input
		t.output = *u.Output
		t.cacheRead = u.CacheRead
		t.cacheWrite = u.CacheWrite
		t.usage = true
	}
	if t.input < 0 || t.output < 0 || t.cacheRead < 0 || t.cacheWrite < 0 {
		t.usage = false
	}
}
func (t *callTrace) cost(kind string, err error) *float64 {
	if t.rates.Unit == "call" {
		if err == nil && t.rates.Call != nil {
			v := *t.rates.Call
			return &v
		}
		return nil
	}
	if !t.usage {
		return nil
	}
	total := 0.0
	for _, x := range []struct {
		n    int64
		rate *float64
	}{{t.input, t.rates.Input}, {t.output, t.rates.Output}, {t.cacheRead, t.rates.CacheRead}, {t.cacheWrite, t.rates.CacheWrite}} {
		if x.n == 0 {
			continue
		}
		if x.rate == nil {
			return nil
		}
		total += float64(x.n) * *x.rate / 1e6
	}
	return &total
}
func (c *Client) beginCall(ctx context.Context, model Model) (context.Context, *callTrace) {
	t := &callTrace{started: time.Now().UTC(), rates: ModelRates{Unit: "tokens"}}
	if c.recorder != nil && model.ID != "" {
		rateCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		err := c.recorder.QueryRowContext(rateCtx, `SELECT unit,input_usd,output_usd,cache_read_usd,cache_write_usd,call_usd FROM ai_model_rates WHERE model_id=$1`, model.ID).Scan(&t.rates.Unit, &t.rates.Input, &t.rates.Output, &t.rates.CacheRead, &t.rates.CacheWrite, &t.rates.Call)
		cancel()
		if err != nil && err != sql.ErrNoRows {
			log.Printf("read model rates: %v", err)
		}
	}
	return context.WithValue(ctx, callTraceKey{}, t), t
}
func (c *Client) endCall(ctx context.Context, model Model, kind string, input any, output string, err error, t *callTrace) {
	if c.recorder == nil || model.ID == "" {
		return
	}
	raw, _ := json.Marshal(input)
	rates, _ := json.Marshal(t.rates)
	status, message := "succeeded", ""
	if err != nil {
		status = "failed"
		message = err.Error()
	}
	// Keys never enter the request transcript. Redact echoes from provider errors.
	redact := func(s string) string {
		if model.APIKey != "" {
			s = strings.ReplaceAll(s, model.APIKey, "[redacted]")
		}
		return truncate(s, 16000)
	}
	recordCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
	defer cancel()
	_, saveErr := c.recorder.ExecContext(recordCtx, `INSERT INTO model_calls
 (id,model_id,model_name,kind,status,request_summary,response_summary,error,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,usage_known,rates,estimated_cost_usd,started_at,finished_at)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,CURRENT_TIMESTAMP)`,
		uuid.NewString(), model.ID, model.ModelName, kind, status, redact(string(raw)), redact(output), redact(message), t.input, t.output, t.cacheRead, t.cacheWrite, t.usage, string(rates), t.cost(kind, err), t.started)
	if saveErr != nil {
		log.Printf("record model call: %v", saveErr)
	}
}
func (c *Client) GenerateText(ctx context.Context, m Model, r GenerateRequest) (string, error) {
	ctx, t := c.beginCall(ctx, m)
	out, err := c.generateText(ctx, m, r)
	c.endCall(ctx, m, "text", r, out, err, t)
	return out, err
}
func (c *Client) GenerateImage(ctx context.Context, m Model, r GenerateImageRequest) (string, error) {
	ctx, t := c.beginCall(ctx, m)
	out, err := c.generateImage(ctx, m, r)
	c.endCall(ctx, m, "image", r, out, err, t)
	return out, err
}
func (c *Client) GenerateSpeech(ctx context.Context, m Model, text, voice string) ([]byte, string, error) {
	ctx, t := c.beginCall(ctx, m)
	out, mime, err := c.generateSpeech(ctx, m, text, voice)
	c.endCall(ctx, m, "speech", map[string]string{"text": text, "voice": voice}, fmt.Sprintf("%s; %d bytes", mime, len(out)), err, t)
	return out, mime, err
}
func (c *Client) TranscribeAudio(ctx context.Context, m Model, filename, mime string, audio []byte) (string, error) {
	ctx, t := c.beginCall(ctx, m)
	out, err := c.transcribeAudio(ctx, m, filename, mime, audio)
	c.endCall(ctx, m, "transcription", map[string]any{"filename": filename, "mime": mime, "bytes": len(audio)}, out, err, t)
	return out, err
}

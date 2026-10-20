package agent

import (
	"errors"
	"math"
	"testing"
)

func rate(v float64) *float64 { return &v }
func TestCallCostUsesReportedUsageAndRateSnapshot(t *testing.T) {
	trace := callTrace{rates: ModelRates{Unit: "tokens", Input: rate(2), Output: rate(8), CacheRead: rate(.2)}}
	trace.readUsage([]byte(`{"usage":{"prompt_tokens":1000,"completion_tokens":100,"prompt_tokens_details":{"cached_tokens":500}}}`))
	cost := trace.cost("text", nil)
	if cost == nil || math.Abs(*cost-.0019) > 1e-10 {
		t.Fatalf("cost=%v", cost)
	}
	trace.rates.CacheRead = nil
	if trace.cost("text", nil) != nil {
		t.Fatal("missing cache rate must remain unpriced")
	}
	trace.usage = false
	if trace.cost("text", nil) != nil {
		t.Fatal("missing usage must remain unpriced")
	}
}
func TestCallCostSuccessfulCallsOnly(t *testing.T) {
	trace := callTrace{rates: ModelRates{Unit: "call", Call: rate(.05)}}
	if got := trace.cost("image", nil); got == nil || *got != .05 {
		t.Fatalf("cost=%v", got)
	}
	if trace.cost("image", errors.New("timeout")) != nil {
		t.Fatal("unknown outcome is not a known zero cost")
	}
}

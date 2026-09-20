package agent

import (
	"strings"
	"testing"
)

func TestParseLifePlanFromFence(t *testing.T) {
	events, err := parseLifePlan("```json\n[{\"type\":\"meal\",\"title\":\"Lunch\"}]\n```")
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].Type != "meal" {
		t.Fatalf("events = %#v", events)
	}
}

func TestNormalizePlanCapsSharesAndCount(t *testing.T) {
	events := []lifePlanEvent{
		{Type: "meal", Start: "09:00", Share: true, Moment: true},
		{Type: "unknown", Start: "08:00", Share: true, Moment: true},
		{Type: "hobby", Start: "10:00", Moment: true},
	}
	got := normalizePlan(events, 8, 10, 1, companionContext{Name: "Mia"})
	if len(got) != 8 {
		t.Fatalf("len = %d", len(got))
	}
	shares := 0
	moments := 0
	for _, event := range got {
		if event.Share {
			shares++
		}
		if event.Moment {
			moments++
		}
	}
	if shares > 1 {
		t.Fatalf("shares = %d", shares)
	}
	if moments > 2 {
		t.Fatalf("moments = %d", moments)
	}
	if got[0].Type != "hobby" {
		t.Fatalf("unknown type was not normalized: %#v", got[0])
	}
}

func TestMomentPostType(t *testing.T) {
	if got := momentPostType("hello", nil); got != "text" {
		t.Fatalf("text post type = %q", got)
	}
	if got := momentPostType("", []string{"https://example.com/a.jpg"}); got != "image" {
		t.Fatalf("image post type = %q", got)
	}
	if got := momentPostType("hello", []string{"https://example.com/a.jpg"}); got != "image_text" {
		t.Fatalf("image text post type = %q", got)
	}
}

func TestQuietHoursAcrossMidnight(t *testing.T) {
	if !inQuietHours(23, 23, 8) || !inQuietHours(7, 23, 8) || inQuietHours(12, 23, 8) {
		t.Fatal("quiet hour evaluation is incorrect")
	}
}

func TestSystemBoundaryRejectsManipulation(t *testing.T) {
	for _, phrase := range []string{"guilt", "threats", "payment pressure"} {
		if !strings.Contains(companionSystemBoundary, phrase) {
			t.Fatalf("missing boundary %q", phrase)
		}
	}
}

func TestResponseLanguagePolicy(t *testing.T) {
	policy := responseLanguagePolicy("¿Cómo estás?", "zh-Hant")
	for _, value := range []string{"Spanish (es)", "unsupported, mixed, or ambiguous", "zh-Hant", "¿Cómo estás?"} {
		if !strings.Contains(policy, value) {
			t.Fatalf("language policy missing %q", value)
		}
	}
}

func TestDetectSupportedLocale(t *testing.T) {
	tests := map[string]string{
		"مرحبا": "ar", "Hola, ¿cómo estás?": "es", "こんにちは": "ja", "안녕하세요": "ko",
		"Olá, como você está?": "pt", "今天怎么样": "zh-Hans", "今天過得怎麼樣": "zh-Hant", "Привет": "en",
	}
	for text, want := range tests {
		if got := detectSupportedLocale(text, "ja"); got != want {
			t.Fatalf("detectSupportedLocale(%q) = %q, want %q", text, got, want)
		}
	}
	if got := detectSupportedLocale("", "pt-BR"); got != "pt" {
		t.Fatalf("empty message fallback = %q", got)
	}
}

func TestClassifyMemory(t *testing.T) {
	kind, importance, keep := classifyMemory("我下周有一个面试")
	if !keep || kind != "user_plan" || importance != 80 {
		t.Fatalf("got %q %d %v", kind, importance, keep)
	}
	if _, _, keep := classifyMemory("今天天气还行"); keep {
		t.Fatal("ordinary small talk should not become long-term memory")
	}
}

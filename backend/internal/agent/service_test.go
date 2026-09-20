package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestGenerateImageUsesFallbackInConfiguredOrder(t *testing.T) {
	primaryCalls := 0
	primary := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		primaryCalls++
		http.Error(w, "primary unavailable", http.StatusServiceUnavailable)
	}))
	defer primary.Close()
	backupCalls := 0
	backup := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		backupCalls++
		_ = json.NewEncoder(w).Encode(map[string]any{"data": []any{map[string]any{"url": "https://cdn.example/fallback.png"}}})
	}))
	defer backup.Close()

	service := &Service{client: NewClient()}
	url, used, err := service.generateImageWithFallback(context.Background(), "companion", "life_photo", []Model{
		{ID: "primary", Kind: "openai", BaseURL: primary.URL, ModelName: "primary"},
		{ID: "backup", Kind: "openai", BaseURL: backup.URL, ModelName: "backup"},
	}, GenerateImageRequest{Prompt: "ordinary life photo"})
	if err != nil {
		t.Fatal(err)
	}
	if url != "https://cdn.example/fallback.png" || used.ID != "backup" {
		t.Fatalf("url = %q, model = %q", url, used.ID)
	}
	if primaryCalls != 1 || backupCalls != 1 {
		t.Fatalf("calls primary=%d backup=%d", primaryCalls, backupCalls)
	}
}

func TestGenerateTextUsesFallbackInConfiguredOrder(t *testing.T) {
	primaryCalls := 0
	primary := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		primaryCalls++
		http.Error(w, "primary unavailable", http.StatusServiceUnavailable)
	}))
	defer primary.Close()
	backupCalls := 0
	backup := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		backupCalls++
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": "fallback reply"}}}})
	}))
	defer backup.Close()

	service := &Service{client: NewClient()}
	text, used, err := service.generateTextWithFallback(context.Background(), "", "reply", []Model{
		{ID: "primary", Kind: "openai", BaseURL: primary.URL, ModelName: "primary"},
		{ID: "backup", Kind: "openai", BaseURL: backup.URL, ModelName: "backup"},
	}, GenerateRequest{Messages: []ChatMessage{{Role: "user", Content: "hello"}}})
	if err != nil {
		t.Fatal(err)
	}
	if text != "fallback reply" || used.ID != "backup" {
		t.Fatalf("text = %q, model = %q", text, used.ID)
	}
	if primaryCalls != 1 || backupCalls != 1 {
		t.Fatalf("calls primary=%d backup=%d", primaryCalls, backupCalls)
	}
}

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
		{Type: "meal", Title: "Breakfast", Description: "Ate breakfast", Location: "home", Start: "09:00", End: "09:30", Importance: 65, Share: true, Moment: true},
		{Type: "unknown", Title: "Morning", Description: "Prepared for the day", Location: "home", Start: "08:00", End: "08:30", Importance: 75, Share: true, Moment: true},
		{Type: "hobby", Title: "Reading", Description: "Read a chapter", Location: "home", Start: "10:00", End: "10:30", Moment: true},
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

func TestNormalizePlanEnforcesCommonSenseShape(t *testing.T) {
	events := []lifePlanEvent{
		{Type: "work", Title: "Valid work", Description: "Finished a report", Location: "office", Start: "09:00", End: "11:00", Importance: 95, MediaURLs: []string{"https://invented.example/image.jpg"}},
		{Type: "meal", Title: "Overlapping meal", Description: "Ate lunch", Location: "cafe", Start: "10:30", End: "11:30", Importance: 90},
		{Type: "hobby", Title: "Impossible clock", Description: "Read", Location: "home", Start: "27:00", End: "28:00", Importance: 80},
		{Type: "hobby", Title: "Too long", Description: "Read", Location: "home", Start: "12:00", End: "20:00", Importance: 80},
		{Type: "meal", Title: "", Description: "Missing title", Location: "home", Start: "18:00", End: "18:30"},
		{Type: "weather", Title: "Invented weather", Description: "Claimed it was raining", Location: "Tokyo", Start: "06:00", End: "06:30"},
	}
	got := normalizePlan(events, 8, 15, 2, companionContext{Name: "Mia", City: "Tokyo"})
	if len(got) < 8 || len(got) > 15 {
		t.Fatalf("event count = %d", len(got))
	}
	high := 0
	for i, event := range got {
		start, startOK := parseClockMinutes(event.Start)
		end, endOK := parseClockMinutes(event.End)
		if !startOK || !endOK || end <= start || end-start < 15 || end-start > 360 {
			t.Fatalf("invalid duration: %#v", event)
		}
		if event.Title == "" || event.Description == "" || event.Location == "" {
			t.Fatalf("incomplete event: %#v", event)
		}
		if event.Importance >= 70 {
			high++
		}
		if i > 0 {
			previousEnd, _ := parseClockMinutes(got[i-1].End)
			if start < previousEnd {
				t.Fatalf("overlap: %#v then %#v", got[i-1], event)
			}
		}
	}
	if high < 2 || high > 5 {
		t.Fatalf("high-importance events = %d", high)
	}
	for _, event := range got {
		if event.Title == "Overlapping meal" || event.Title == "Impossible clock" || event.Title == "Too long" || event.Title == "Invented weather" {
			t.Fatalf("invalid event survived normalization: %#v", event)
		}
		if len(event.MediaURLs) != 0 {
			t.Fatalf("unverified media URL survived normalization: %#v", event)
		}
	}
}

func TestLifePlanPromptCarriesIdentityAndContinuity(t *testing.T) {
	prompt := lifePlanPrompt(companionContext{
		Name: "Mia", City: "Tokyo", Occupation: "designer", Interests: "photography",
		PersonalityTags: "thoughtful", SpeakingStyle: "concise", Likes: "coffee",
		Dislikes: "crowds", LifeHabits: "morning walk", LifeGoal: "open a studio",
		Backstory: "moved recently", Persona: "independent",
	}, "2026-09-20", "Asia/Tokyo", "2026-09-19 gallery visit", 8, 24, 3)
	for _, expected := range []string{
		"Asia/Tokyo", "morning walk", "open a studio", "moved recently",
		"2026-09-19 gallery visit", "non-overlapping", "Do not invent real-time weather",
		"8 to 15 objects",
	} {
		if !strings.Contains(prompt, expected) {
			t.Fatalf("prompt missing %q", expected)
		}
	}
}

func TestReasonableSocialHour(t *testing.T) {
	for _, hour := range []int{8, 12, 20} {
		if !reasonableSocialHour(hour) {
			t.Fatalf("hour %d should be allowed", hour)
		}
	}
	for _, hour := range []int{0, 7, 21, 23} {
		if reasonableSocialHour(hour) {
			t.Fatalf("hour %d should be blocked", hour)
		}
	}
}

func TestEmojiMessagePolicyKeepsEmojiNatural(t *testing.T) {
	for _, expected := range []string{"Emoji are supported", "0 to 2 emoji", "speaking style", "Do not add emoji mechanically"} {
		if !strings.Contains(emojiMessagePolicy, expected) {
			t.Fatalf("emoji policy missing %q", expected)
		}
	}
}

func TestReplyDelayForBusyEventIsShortAndBounded(t *testing.T) {
	now := time.Date(2026, 9, 20, 10, 0, 0, 0, time.UTC)
	if got := replyDelayForEvent("commute", now.Add(time.Hour), now); got != 2*time.Minute {
		t.Fatalf("commute delay = %s", got)
	}
	if got := replyDelayForEvent("work", now.Add(time.Hour), now); got != 5*time.Minute {
		t.Fatalf("work delay = %s", got)
	}
	if got := replyDelayForEvent("work", now.Add(10*time.Second), now); got != 15*time.Second {
		t.Fatalf("minimum delay = %s", got)
	}
}

func TestInferFollowUpAtUsesUserLocalEvening(t *testing.T) {
	location := time.FixedZone("UTC+8", 8*60*60)
	now := time.Date(2026, 9, 20, 11, 30, 0, 0, location)
	tomorrow := inferFollowUpAt("我明天有面试", now)
	if tomorrow.Day() != 21 || tomorrow.Hour() != 18 || tomorrow.Location() != location {
		t.Fatalf("tomorrow follow-up = %v", tomorrow)
	}
	nextWeek := inferFollowUpAt("next week I have an exam", now)
	if nextWeek.Day() != 27 || nextWeek.Hour() != 18 {
		t.Fatalf("next-week follow-up = %v", nextWeek)
	}
}

func TestStringSliceFiltersEmptyMedia(t *testing.T) {
	got := stringSlice([]any{"https://example.com/a.jpg", " ", 3})
	if len(got) != 1 || got[0] != "https://example.com/a.jpg" {
		t.Fatalf("media = %#v", got)
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

func TestOrderedModelCandidateIDsPrefersNewestSubscriptionModels(t *testing.T) {
	got := orderedModelCandidateIDs([]string{"plus-newest", "plus-older"}, "standard-primary", []string{"standard-backup"})
	if strings.Join(got, ",") != "plus-newest,plus-older,standard-primary,standard-backup" {
		t.Fatalf("model candidates = %v", got)
	}
}

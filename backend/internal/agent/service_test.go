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
		{Type: "meal", Start: "09:00", Share: true},
		{Type: "unknown", Start: "08:00", Share: true},
	}
	got := normalizePlan(events, 8, 10, 1, companionContext{Name: "Mia"})
	if len(got) != 8 {
		t.Fatalf("len = %d", len(got))
	}
	shares := 0
	for _, event := range got {
		if event.Share {
			shares++
		}
	}
	if shares > 1 {
		t.Fatalf("shares = %d", shares)
	}
	if got[0].Type != "hobby" {
		t.Fatalf("unknown type was not normalized: %#v", got[0])
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

func TestClassifyMemory(t *testing.T) {
	kind, importance, keep := classifyMemory("我下周有一个面试")
	if !keep || kind != "user_plan" || importance != 80 {
		t.Fatalf("got %q %d %v", kind, importance, keep)
	}
	if _, _, keep := classifyMemory("今天天气还行"); keep {
		t.Fatal("ordinary small talk should not become long-term memory")
	}
}

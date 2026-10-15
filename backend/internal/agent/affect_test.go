package agent

import (
	"strings"
	"testing"
	"time"
)

func TestAffectMetadataIsBoundedAndOptional(t *testing.T) {
	base := `{"messages":["我想先安静一会儿。"],"follow_up":null,"affect":`
	valid := `{"version":2,"feeling":"irritated","reason":"The actual conversation was hurtful.","mood":-2,"stress":1,"social":-2,"energy":0,"action":"space"}`
	turn, err := decodeConversationalTurn("```json\n" + base + valid + "}\n```")
	if err != nil || turn.Affect == nil || turn.Affect.Version != 2 || len(turn.Messages) != 1 {
		t.Fatalf("valid metadata lost: %+v, %v", turn, err)
	}
	for _, metadata := range []string{
		`null`, `"not an object"`, `{"version":2,"feeling":"irritated","reason":"x","mood":100,"action":"space"}`,
		`{"version":2,"feeling":"irritated","reason":"x","mood":-2,"action":"cancel_purchase"}`,
		`{"version":-1,"feeling":"calm","reason":"x","action":"open"}`,
	} {
		turn, err := decodeConversationalTurn(base + metadata + "}")
		if err != nil || turn.Affect != nil || len(turn.Messages) != 1 {
			t.Fatalf("invalid optional state blocked/leaked into reply: %s %+v %v", metadata, turn, err)
		}
	}
	if _, err := decodeConversationalTurn(`Here is the private data: {"affect":{}}`); err == nil {
		t.Fatal("metadata outside a valid envelope may leak into chat")
	}
}

func TestWaitingExcludesQuietHours(t *testing.T) {
	first := time.Date(2026, 10, 14, 22, 0, 0, 0, time.UTC)
	p := ContactPreferences{QuietEnabled: true, QuietStart: 23, QuietEnd: 8}
	if got := awakeWaitingTime(first, first.Add(12*time.Hour), "UTC", p); got != 3*time.Hour {
		t.Fatalf("night counted as ignored attention: %s", got)
	}
	p.QuietEnabled = false
	if got := awakeWaitingTime(first, first.Add(12*time.Hour), "UTC", p); got != 12*time.Hour {
		t.Fatal(got)
	}
}

func TestLifeAffectUsesFactsAndKeepsUnicode(t *testing.T) {
	positive, ok := lifeAffect("content", "hobby", "Finished a small drawing")
	if !ok || positive.Mood <= 0 || !validAffect(&positive) {
		t.Fatal("positive life not represented")
	}
	negative, ok := lifeAffect("frustrated", "work", strings.Repeat("工作有些不顺利", 40))
	if !ok || negative.Mood >= 0 || negative.Energy >= 0 || negative.Action != "slow" || !validAffect(&negative) {
		t.Fatalf("negative event invalid: %+v", negative)
	}
	if _, ok := lifeAffect("invented_emotion", "unknown", "x"); ok {
		t.Fatal("invented emotion applied")
	}
}

package agent

import (
	"strings"
	"testing"
	"time"
)

func TestParseMemoryExtractionRejectsUnsafeUpdatesAndDates(t *testing.T) {
	now := time.Date(2026, 10, 12, 4, 0, 0, 0, time.UTC)
	for _, raw := range []string{
		`{}`, `{"memories":null,"updates":[]}`,
		`{"memories":[],"updates":[{"id":"other-user","status":"resolved"}]}`,
		`{"memories":[],"updates":[{"id":"known","status":"active"}]}`,
		`{"memories":[{"type":"user_plan","content":"Interview","importance":80,"follow_up_at":"2026-10-12T03:00:00Z"}],"updates":[]}`,
		`{"memories":[{"type":"user_boundary","content":"No reminders","importance":90,"follow_up_at":"2026-10-13T10:00:00Z"}],"updates":[]}`,
		`{"memories":[{"type":"user_plan","content":"Interview","importance":80,"event_at":"2026-10-13T12:00:00+08:00","follow_up_at":"2026-10-13T11:00:00+08:00"}],"updates":[]}`,
		`{"memories":[],"updates":[],"relationship":{"stage":"married","user_evidence":"yes","assistant_evidence":"yes"}}`,
	} {
		if _, err := parseMemoryExtraction(raw, map[string]bool{"known": true}, now); err == nil {
			t.Fatalf("accepted invalid output: %s", raw)
		}
	}
	got, err := parseMemoryExtraction(`{"memories":[{"type":"user_plan","content":"明天下午面试","importance":80,"event_at":"2026-10-13T14:00:00+08:00","follow_up_at":"2026-10-13T18:00:00+08:00"}],"updates":[{"id":"known","status":"superseded"}],"relationship":null}`, map[string]bool{"known": true}, now)
	if err != nil || len(got.Memories) != 1 {
		t.Fatalf("valid memory: %+v, %v", got, err)
	}
}

func TestRelationshipEvidenceRequiresBothPartiesInCurrentExchange(t *testing.T) {
	cases := []struct {
		name      string
		messages  []ChatMessage
		agreement relationshipAgreement
		valid     bool
	}{
		{"user proposes", []ChatMessage{{Role: "user", Content: "Let's be partners."}, {Role: "assistant", Content: "Yes, let's be partners."}}, relationshipAgreement{Stage: "partner", UserEvidence: "Let's be partners.", AssistantEvidence: "Yes, let's be partners."}, true},
		{"companion proposes", []ChatMessage{{Role: "assistant", Content: "Would you like to be partners?"}, {Role: "user", Content: "Yes, I want to be your partner."}, {Role: "assistant", Content: "I'm glad."}}, relationshipAgreement{Stage: "partner", UserEvidence: "Yes, I want to be your partner.", AssistantEvidence: "Would you like to be partners?"}, true},
		{"invented user agreement", []ChatMessage{{Role: "assistant", Content: "Be my partner?"}, {Role: "user", Content: "No."}}, relationshipAgreement{Stage: "partner", UserEvidence: "Yes", AssistantEvidence: "Be my partner?"}, false},
		{"old consent is not new consent", []ChatMessage{{Role: "user", Content: "Yes"}, {Role: "assistant", Content: "Partners"}, {Role: "user", Content: "Stop"}}, relationshipAgreement{Stage: "partner", UserEvidence: "Yes", AssistantEvidence: "Partners"}, false},
		{"invented companion agreement", []ChatMessage{{Role: "user", Content: "Be my partner?"}}, relationshipAgreement{Stage: "partner", UserEvidence: "Be my partner?", AssistantEvidence: "Yes"}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateRelationshipEvidence(&tc.agreement, tc.messages)
			if (err == nil) != tc.valid {
				t.Fatalf("valid=%v, err=%v", tc.valid, err)
			}
		})
	}
}

func TestContactPreferencesValidation(t *testing.T) {
	p := ContactPreferences{DailyLimit: 4, MinimumGapMinutes: 120, QuietEnabled: true, QuietStart: 23, QuietEnd: 8}
	if err := p.Validate(); err != nil {
		t.Fatal(err)
	}
	for _, bad := range []ContactPreferences{
		{DailyLimit: 9, MinimumGapMinutes: 120}, {DailyLimit: 1, MinimumGapMinutes: 0},
		{DailyLimit: 1, MinimumGapMinutes: 120, QuietEnabled: true, QuietStart: 8, QuietEnd: 8},
		{DailyLimit: 1, MinimumGapMinutes: 120, QuietStart: 24},
	} {
		if bad.Validate() == nil {
			t.Fatalf("invalid preferences: %+v", bad)
		}
	}
	p.DailyLimit = 0
	p.QuietEnabled = false
	p.QuietEnd = p.QuietStart
	if err := p.Validate(); err != nil {
		t.Fatal(err)
	}
}

func TestContinuityPoliciesRespectCharacterAndConsent(t *testing.T) {
	for _, phrase := range []string{"latest user correction", "explicit user boundaries", "Either you or the user", "wait for the other party", "truthful that you are an AI"} {
		if !strings.Contains(companionSystemBoundary, phrase) {
			t.Fatalf("missing %q", phrase)
		}
	}
	if !strings.Contains(memoryExtractionPolicy, "A unilateral proposal") || !strings.Contains(memoryExtractionPolicy, "cancel abandoned plans") {
		t.Fatal("missing continuity rules")
	}
}

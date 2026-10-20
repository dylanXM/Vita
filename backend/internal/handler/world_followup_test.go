package handler

import (
	"testing"
	"time"
	"vita/internal/agent"
)

func TestTrialWorldVisitFollowupRespectsDeadlineAndQuietHours(t *testing.T) {
	zone := time.FixedZone("Asia/Shanghai", 8*60*60)
	now := time.Date(2026, 10, 13, 10, 0, 0, 0, zone)
	expiry := now.Add(8 * time.Hour)
	preferences := agent.ContactPreferences{DailyLimit: 4, MinimumGapMinutes: 120, QuietEnabled: true, QuietStart: 23, QuietEnd: 8}
	got := worldVisitFollowupAt(now, &expiry, preferences)
	if got == nil || !got.Equal(now.Add(2*time.Hour)) {
		t.Fatalf("trial followup=%v", got)
	}
	short := now.Add(2 * time.Hour)
	if worldVisitFollowupAt(now, &short, preferences) != nil {
		t.Fatal("scheduled too close to expiry")
	}
	late := time.Date(2026, 10, 13, 22, 0, 0, 0, zone)
	deadline := late.Add(12 * time.Hour)
	got = worldVisitFollowupAt(late, &deadline, preferences)
	if got == nil || got.Hour() != 8 || got.Day() != 14 {
		t.Fatalf("quiet-hours followup=%v", got)
	}
	preferences.DailyLimit = 0
	if worldVisitFollowupAt(now, &expiry, preferences) != nil {
		t.Fatal("ignored contact opt-out")
	}
}

func TestSubscriberWorldVisitKeepsNextDayRhythm(t *testing.T) {
	now := time.Date(2026, 10, 13, 10, 0, 0, 0, time.UTC)
	got := worldVisitFollowupAt(now, nil, agent.ContactPreferences{DailyLimit: 4, MinimumGapMinutes: 120})
	if got == nil || got.Day() != 14 || got.Hour() != 18 {
		t.Fatalf("subscriber followup=%v", got)
	}
}

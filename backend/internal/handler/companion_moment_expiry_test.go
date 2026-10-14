package handler

import (
	"testing"
	"time"
)

func TestCompanionMomentFixedDeadline(t *testing.T) {
	end := time.Date(2026, 10, 14, 15, 0, 0, 0, time.UTC)
	for _, opening := range []string{"", "Welcome"} {
		moment := companionMoment{StartsAt: end.Add(-time.Hour), EndsAt: end, Opening: opening}
		if moment.ended(end.Add(-time.Nanosecond)) {
			t.Fatal("date ended before scheduled deadline")
		}
		if !moment.ended(end) || !moment.ended(end.Add(time.Hour)) {
			t.Fatalf("date remains open after deadline; opening=%q", opening)
		}
	}
}

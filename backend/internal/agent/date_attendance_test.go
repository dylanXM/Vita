package agent

import (
	"testing"
	"time"
)

func TestDateAttendanceStage(t *testing.T) {
	start := time.Date(2026, 10, 13, 12, 0, 0, 0, time.UTC)
	end := start.Add(time.Hour)
	for _, tc := range []struct {
		name         string
		now          time.Time
		late, missed bool
		want         string
	}{
		{"on time", start, false, false, ""},
		{"five minute grace", start.Add(5 * time.Minute), false, false, ""},
		{"late", start.Add(5*time.Minute + time.Second), false, false, "late"},
		{"late processed", start.Add(10 * time.Minute), true, false, ""},
		{"missed without prior tick", end, false, false, "missed"},
		{"escalate once", end, true, false, "missed"},
		{"missed processed", end.Add(time.Hour), true, true, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := dateAttendanceStage(tc.now, start, end, tc.late, tc.missed); got != tc.want {
				t.Fatalf("got %q want %q", got, tc.want)
			}
		})
	}
}

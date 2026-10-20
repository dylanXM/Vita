package handler

import (
	"time"
	"vita/internal/agent"
)

// Preserve the usual next-day rhythm for subscribers. Trial visits get one
// earlier continuation, without overriding quiet hours or the contact interval.
func worldVisitFollowupAt(now time.Time, expires *time.Time, p agent.ContactPreferences) *time.Time {
	target := time.Date(now.Year(), now.Month(), now.Day()+1, 18, 0, 0, 0, now.Location())
	if expires != nil {
		gap := max(30, p.MinimumGapMinutes)
		target = now.Add(time.Duration(gap) * time.Minute)
	}
	if p.QuietEnabled {
		hour := target.Hour()
		quiet := p.QuietStart < p.QuietEnd && hour >= p.QuietStart && hour < p.QuietEnd || p.QuietStart > p.QuietEnd && (hour >= p.QuietStart || hour < p.QuietEnd)
		if quiet {
			day := target.Day()
			if p.QuietStart > p.QuietEnd && hour >= p.QuietStart {
				day++
			}
			target = time.Date(target.Year(), target.Month(), day, p.QuietEnd, 0, 0, 0, target.Location())
		}
	}
	if p.DailyLimit == 0 || expires != nil && !target.Add(15*time.Minute).Before(*expires) {
		return nil
	}
	return &target
}

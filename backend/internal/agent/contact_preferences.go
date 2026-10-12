package agent

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

type ContactPreferences struct {
	DailyLimit        int  `json:"daily_limit"`
	MinimumGapMinutes int  `json:"minimum_gap_minutes"`
	QuietEnabled      bool `json:"quiet_enabled"`
	QuietStart        int  `json:"quiet_start"`
	QuietEnd          int  `json:"quiet_end"`
}

func (p ContactPreferences) Validate() error {
	if p.DailyLimit < 0 || p.DailyLimit > 8 || p.MinimumGapMinutes < 30 || p.MinimumGapMinutes > 1440 || p.QuietStart < 0 || p.QuietStart > 23 || p.QuietEnd < 0 || p.QuietEnd > 23 || (p.QuietEnabled && p.QuietStart == p.QuietEnd) {
		return fmt.Errorf("invalid contact preferences")
	}
	return nil
}

type contactQuerier interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func LoadContactPreferences(ctx context.Context, q contactQuerier, userID string) (ContactPreferences, error) {
	var p ContactPreferences
	err := q.QueryRowContext(ctx, `SELECT daily_limit,minimum_gap_minutes,quiet_enabled,quiet_start,quiet_end FROM user_contact_preferences WHERE user_id=$1`, userID).Scan(&p.DailyLimit, &p.MinimumGapMinutes, &p.QuietEnabled, &p.QuietStart, &p.QuietEnd)
	if errors.Is(err, sql.ErrNoRows) {
		err = q.QueryRowContext(ctx, `SELECT daily_proactive_limit,quiet_hours_start,quiet_hours_end FROM agent_settings WHERE id='default'`).Scan(&p.DailyLimit, &p.QuietStart, &p.QuietEnd)
		p.MinimumGapMinutes = 120
		p.QuietEnabled = p.QuietStart != p.QuietEnd
	}
	return p, err
}

// All autonomous contact shares one account-wide budget, including follow-ups.
// The transaction caller locks the user row before this final eligibility check.
func (s *Service) contactAllowed(ctx context.Context, q contactQuerier, userID, timezone string, settings lifeSettings) (bool, error) {
	p, err := LoadContactPreferences(ctx, q, userID)
	if err != nil {
		return false, err
	}
	location, err := time.LoadLocation(timezone)
	if err != nil {
		location = time.UTC
	}
	now := time.Now().In(location)
	if p.DailyLimit == 0 || settings.DailyProactiveLimit == 0 || (p.QuietEnabled && inQuietHours(now.Hour(), p.QuietStart, p.QuietEnd)) {
		return false, nil
	}
	start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, location).UTC()
	end := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, location).UTC()
	var count int
	var latest sql.NullTime
	err = q.QueryRowContext(ctx, `SELECT COUNT(*) FILTER (WHERE m.created_at>=$2 AND m.created_at<$3),MAX(m.created_at)
 FROM messages m JOIN conversations c ON c.id=m.conversation_id
 WHERE c.user_id=$1 AND m.source IN ('proactive','memory_followup')`, userID, start, end).Scan(&count, &latest)
	if err != nil {
		return false, err
	}
	if count >= min(p.DailyLimit, settings.DailyProactiveLimit) || (latest.Valid && time.Since(latest.Time) < time.Duration(p.MinimumGapMinutes)*time.Minute) {
		return false, nil
	}
	var present bool
	err = q.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM messages m JOIN conversations c ON c.id=m.conversation_id
 WHERE c.user_id=$1 AND m.sender_type='user' AND m.created_at>CURRENT_TIMESTAMP-INTERVAL '20 minutes')
 OR EXISTS(SELECT 1 FROM world_interactions WHERE user_id=$1 AND kind IN ('visit','chat') AND created_at>CURRENT_TIMESTAMP-INTERVAL '20 minutes')`, userID).Scan(&present)
	return !present, err
}

func (s *Service) lockContact(ctx context.Context, tx *sql.Tx, userID, timezone string, settings lifeSettings) (bool, error) {
	var id string
	if err := tx.QueryRowContext(ctx, `SELECT id FROM users WHERE id=$1 FOR UPDATE`, userID).Scan(&id); err != nil {
		return false, err
	}
	return s.contactAllowed(ctx, tx, userID, timezone, settings)
}

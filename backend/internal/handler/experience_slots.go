package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"vita/internal/db"
)

type experienceBlock struct{ Start, End time.Time }
type experienceSlot struct {
	StartsAt time.Time `json:"starts_at"`
	EndsAt   time.Time `json:"ends_at"`
}

// Routine leisure can be rearranged. Work, study, commuting and existing paid
// shared activities remain hard commitments for both listing and submission.
func loadExperienceBlocks(ctx context.Context, companionID string, from, to time.Time) ([]experienceBlock, error) {
	rows, err := db.Get().QueryContext(ctx, `SELECT start_time,end_time FROM life_events WHERE companion_id=$1 AND status IN ('active','scheduled') AND end_time>$2 AND start_time<$3 AND (event_type IN ('work','study','commute') OR (event_type='shared_activity' AND generation_source='user_purchase')) ORDER BY start_time,end_time`, companionID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var blocks []experienceBlock
	for rows.Next() {
		var b experienceBlock
		if err = rows.Scan(&b.Start, &b.End); err != nil {
			return nil, err
		}
		blocks = append(blocks, b)
	}
	return blocks, rows.Err()
}

func fitsExperienceSlot(start time.Time, duration time.Duration, blocks []experienceBlock) bool {
	for _, b := range blocks {
		if start.Before(b.End) && start.Add(duration).After(b.Start) {
			return false
		}
	}
	return true
}

func availableExperienceSlots(now time.Time, duration time.Duration, blocks []experienceBlock) []experienceSlot {
	slots := make([]experienceSlot, 0, 12)
	if duration <= 0 || duration > 24*time.Hour {
		return slots
	}
	earliest := now.UTC().Add(10 * time.Minute)
	candidate := earliest.Truncate(15 * time.Minute)
	if candidate.Before(earliest) {
		candidate = candidate.Add(15 * time.Minute)
	}
	horizon := now.UTC().Add(7 * 24 * time.Hour)
	for !candidate.Add(duration).After(horizon) && len(slots) < 12 {
		if fitsExperienceSlot(candidate, duration, blocks) {
			slots = append(slots, experienceSlot{candidate, candidate.Add(duration)})
			candidate = candidate.Add(30 * time.Minute)
		} else {
			candidate = candidate.Add(15 * time.Minute)
		}
	}
	return slots
}

func ListExperienceSlots(c *gin.Context) {
	companionID, userID := c.Param("id"), c.GetString("user_id")
	if !requireExperienceCompanion(c, userID, companionID) {
		return
	}
	var raw string
	var launched bool
	err := db.Get().QueryRowContext(c.Request.Context(), `SELECT metadata::text,is_launched FROM credit_products WHERE environment=$1 AND product_key=$2 AND category='date' AND enabled=true`, currentEnvironment(), c.Param("product_key")).Scan(&raw, &launched)
	if err != nil {
		c.JSON(404, gin.H{"error": "date experience unavailable"})
		return
	}
	if !launched {
		c.JSON(409, gin.H{"error": "date experience not launched"})
		return
	}
	metadata := map[string]any{}
	if json.Unmarshal([]byte(raw), &metadata) != nil {
		c.JSON(500, gin.H{"error": "invalid date configuration"})
		return
	}
	duration := time.Duration(metadataInt(metadata, "duration_minutes", 60)) * time.Minute
	if duration <= 0 || duration > 24*time.Hour {
		c.JSON(500, gin.H{"error": "invalid date duration"})
		return
	}
	now := time.Now().UTC()
	blocks, err := loadExperienceBlocks(c.Request.Context(), companionID, now, now.Add(8*24*time.Hour))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load available times"})
		return
	}
	c.JSON(200, gin.H{"slots": availableExperienceSlots(now, duration, blocks), "server_time": now})
}

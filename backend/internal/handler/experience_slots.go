package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
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

// Check this companion's hard routine commitments and the user's booked dates
// across all companions. Listing and submission share the same overlap rules.
func loadExperienceBlocks(ctx context.Context, companionID string, from, to time.Time) ([]experienceBlock, error) {
	rows, err := db.Get().QueryContext(ctx, `SELECT e.start_time,e.end_time FROM life_events e
 JOIN companions booked ON booked.id=e.companion_id
 WHERE e.status IN ('active','scheduled') AND e.end_time>$2 AND e.start_time<$3
 AND ((e.companion_id=$1 AND e.event_type IN ('work','study','commute'))
 OR (e.event_type='shared_activity' AND e.generation_source='user_purchase'
 AND booked.user_id=(SELECT user_id FROM companions WHERE id=$1)))
 ORDER BY e.start_time,e.end_time`, companionID, from, to)
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
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(404, gin.H{"error": "date experience unavailable"})
		return
	}
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to load date experience"})
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

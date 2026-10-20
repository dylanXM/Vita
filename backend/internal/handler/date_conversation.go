package handler

import (
	"context"
	"database/sql"
	"errors"

	"vita/internal/db"
)

// New dates have their own conversation and pending-reply queue. Existing dates
// retain their original conversation; the date message filter isolates history.
func dateConversation(ctx context.Context, userID, companionID, eventID string, createDedicated ...bool) (string, error) {
	var id string
	err := db.Get().QueryRowContext(ctx, `SELECT m.conversation_id FROM messages m JOIN conversations cv ON cv.id=m.conversation_id WHERE cv.user_id=$1 AND cv.companion_id=$2 AND m.life_event_id=$3 AND m.source IN ('moment_opening','moment_preparation') ORDER BY m.created_at,m.id LIMIT 1`, userID, companionID, eventID).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}
	id = "date:" + eventID
	if len(createDedicated) == 0 || !createDedicated[0] {
		var existing string
		lookupErr := db.Get().QueryRowContext(ctx, `SELECT id FROM conversations WHERE id=$1 AND user_id=$2 AND companion_id=$3`, id, userID, companionID).Scan(&existing)
		if lookupErr == nil {
			return existing, nil
		}
		if !errors.Is(lookupErr, sql.ErrNoRows) {
			return "", lookupErr
		}
		// Older Apps do not ask for a date conversation. Keep their original
		// interaction path until they update; new Apps create it before starting.
		return experienceConversation(ctx, userID, companionID)
	}

	_, err = db.Get().ExecContext(ctx, `INSERT INTO conversations(id,user_id,companion_id) VALUES($1,$2,$3) ON CONFLICT(id) DO NOTHING`, id, userID, companionID)
	return id, err
}

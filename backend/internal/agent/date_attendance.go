package agent

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"
)

// DateAttendanceStage records an escalating impact, rather than charging twice.
func dateAttendanceStage(now, start, end time.Time, late, missed bool) string {
	if !now.Before(end) && !missed {
		return "missed"
	}
	if now.After(start.Add(5*time.Minute)) && now.Before(end) && !late && !missed {
		return "late"
	}
	return ""
}

// ProcessDateAttendance is also called before a late arrival starts the scene,
// so scheduler timing cannot erase the original appointment's consequences.
func (s *Service) ProcessDateAttendance(ctx context.Context, eventID string) error {
	var userID, companionID, title, location string
	var start, end time.Time
	var late, missed bool
	err := s.db.QueryRowContext(ctx, `SELECT c.user_id,e.companion_id,COALESCE(e.title,''),COALESCE(e.location,''),e.start_time,e.end_time,
 COALESCE(e.payload->>'attendance_late','')='true',COALESCE(e.payload->>'attendance_missed','')='true'
 FROM life_events e JOIN companions c ON c.id=e.companion_id
 WHERE e.id=$1 AND c.active=true AND e.event_type='shared_activity' AND e.generation_source='user_purchase'
 AND e.status IN ('active','scheduled')
 AND (NULLIF(e.payload->>'attendance_entering_at','')::timestamptz IS NULL OR NULLIF(e.payload->>'attendance_entering_at','')::timestamptz<=CURRENT_TIMESTAMP-INTERVAL '2 minutes')
 AND NOT EXISTS(SELECT 1 FROM companion_moment_sessions ms WHERE ms.event_id=e.id AND ms.opening_message_id IS NOT NULL)
 AND EXISTS(SELECT 1 FROM credit_spends p WHERE p.reference_id=e.id AND p.user_id=c.user_id AND p.companion_id=c.id AND p.status='completed' AND p.reference_type='companion_experience')`, eventID).Scan(&userID, &companionID, &title, &location, &start, &end, &late, &missed)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return err
	}
	stage := dateAttendanceStage(time.Now(), start, end, late, missed)
	if stage == "" {
		return nil
	}
	// Bound provider work and always retain a localized, factual fallback.
	reactionCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	var reaction affectChange
	text := s.ComposeInteractionReaction(reactionCtx, userID, companionID, "date_attendance", fmt.Sprintf("%s at %s, scheduled %s to %s; user has not entered", title, location, start.Format(time.RFC3339), end.Format(time.RFC3339)), stage, &reaction)
	cancel()
	if text == "" {
		return fmt.Errorf("date attendance: empty reaction for %s", eventID)
	}
	conversationID, err := s.getOrCreateConversation(ctx, userID, companionID)
	if err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	// StartCompanionMoment takes the same event row lock before saving its opening.
	var lockedID string
	if err = tx.QueryRowContext(ctx, `SELECT id FROM life_events WHERE id=$1 FOR UPDATE`, eventID).Scan(&lockedID); err != nil {
		return err
	}
	var entered bool
	if err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM companion_moment_sessions WHERE event_id=$1 AND opening_message_id IS NOT NULL) OR EXISTS(SELECT 1 FROM life_events WHERE id=$1 AND NULLIF(payload->>'attendance_entering_at','')::timestamptz>CURRENT_TIMESTAMP-INTERVAL '2 minutes')`, eventID).Scan(&entered); err != nil {
		return err
	}
	if entered {
		return nil
	}
	if err = tx.QueryRowContext(ctx, `SELECT start_time,end_time,COALESCE(payload->>'attendance_late','')='true',COALESCE(payload->>'attendance_missed','')='true' FROM life_events WHERE id=$1`, eventID).Scan(&start, &end, &late, &missed); err != nil {
		return err
	}
	if dateAttendanceStage(time.Now(), start, end, late, missed) != stage {
		return nil
	}
	modelAffect := validAffect(&reaction)
	if !modelAffect {
		// Deterministic fallback, only when the existing reaction call is unavailable.
		var relationship string
		var stress int
		if err := tx.QueryRowContext(ctx, `SELECT COALESCE(c.relationship_stage,'stranger'),COALESCE(st.stress,50) FROM companions c LEFT JOIN companion_states st ON st.companion_id=c.id WHERE c.id=$1`, companionID).Scan(&relationship, &stress); err != nil {
			return err
		}
		penalty := 1
		if relationship == "close" || relationship == "partner" {
			penalty++
		}
		if stage == "missed" || stress > 70 {
			penalty++
		}
		reaction = affectChange{Feeling: "sad", Reason: "Recorded date attendance: " + stage, Mood: -penalty, Stress: 1, Social: -1, Action: "slow"}
	}
	marker := "attendance_" + stage
	if _, err = tx.ExecContext(ctx, `UPDATE life_events SET payload=jsonb_set(COALESCE(payload,'{}'::jsonb),ARRAY[$2::text],'true'::jsonb) WHERE id=$1`, eventID, marker); err != nil {
		return err
	}
	if err = applyAffect(ctx, tx, companionID, "attendance:"+eventID+":"+stage, reaction, modelAffect); err != nil {
		return err
	}
	id := "date-attendance:" + eventID + ":" + stage
	payload, _ := json.Marshal(map[string]any{"conversation_channel": "chat", "life_event_context_id": eventID, "event_title": title, "event_location": location, "attendance_stage": stage})
	if _, err = tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,delivery_status)
 VALUES($1,$2,'assistant','text',$3,$4::jsonb,'date_attendance','delivered')`, id, conversationID, text, string(payload)); err != nil {
		return err
	}
	fact := fmt.Sprintf("The user was %s for our booked virtual date (%s, %s, scheduled %s to %s). My recorded reaction was: %s. This is one incident, not a permanent user trait. Later feelings and actions depend on actual context; neither a return nor an apology automatically resolves it.", stage, title, location, start.Format(time.RFC3339), end.Format(time.RFC3339), text)
	if _, err = tx.ExecContext(ctx, `INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata) VALUES($1,$2,'emotional_context',$3,80,$4,$5)`, id, companionID, fact, start, string(payload)); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Service) ProcessDueDateAttendance(ctx context.Context) error {
	rows, err := s.db.QueryContext(ctx, `SELECT e.id FROM life_events e JOIN companions c ON c.id=e.companion_id
 WHERE c.active=true AND e.event_type='shared_activity' AND e.generation_source='user_purchase' AND e.status IN ('active','scheduled')
 AND (NULLIF(e.payload->>'attendance_entering_at','')::timestamptz IS NULL OR NULLIF(e.payload->>'attendance_entering_at','')::timestamptz<=CURRENT_TIMESTAMP-INTERVAL '2 minutes')
 AND (NULLIF(e.payload->>'attendance_entering_at','')::timestamptz IS NULL OR NULLIF(e.payload->>'attendance_entering_at','')::timestamptz<=CURRENT_TIMESTAMP-INTERVAL '2 minutes')
 AND e.start_time<CURRENT_TIMESTAMP-INTERVAL '5 minutes'
 AND COALESCE(e.payload->>'attendance_missed','')<>'true'
 AND (e.end_time<=CURRENT_TIMESTAMP OR COALESCE(e.payload->>'attendance_late','')<>'true')
 AND NOT EXISTS(SELECT 1 FROM companion_moment_sessions ms WHERE ms.event_id=e.id AND ms.opening_message_id IS NOT NULL)
 AND EXISTS(SELECT 1 FROM credit_spends p WHERE p.reference_id=e.id AND p.user_id=c.user_id AND p.companion_id=c.id AND p.status='completed' AND p.reference_type='companion_experience')
 ORDER BY e.end_time ASC,e.id ASC LIMIT 2`)
	if err != nil {
		return err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err = s.ProcessDateAttendance(ctx, id); err != nil {
			return err
		}
	}
	return nil
}

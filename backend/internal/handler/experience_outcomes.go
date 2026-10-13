package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"vita/internal/db"
)

type experienceOutcomeInput struct {
	EventID           string `json:"event_id"`
	SpendID           string `json:"spend_id"`
	ProposalMessageID string `json:"proposal_message_id"`
	Title             string `json:"title"`
}

type experienceOutcome struct {
	Title             string `json:"title"`
	Challenge         string `json:"challenge"`
	Decision          string `json:"decision"`
	Note              string `json:"note"`
	MemoryID          string `json:"memory_id"`
	EventID           string `json:"event_id,omitempty"`
	SpendID           string `json:"spend_id,omitempty"`
	ProposalMessageID string `json:"proposal_message_id"`
}

func outcomeIdentity(eventID, spendID string) (string, error) {
	if (eventID == "") == (spendID == "") || len(eventID) > 128 || len(spendID) > 128 {
		return "", fmt.Errorf("exactly one experience reference is required")
	}
	if eventID != "" {
		return "experience-outcome:event:" + eventID, nil
	}
	return "experience-outcome:spend:" + spendID, nil
}

func readExperienceOutcome(ctx context.Context, userID, companionID, id string) (*experienceOutcome, error) {
	var raw string
	err := db.Get().QueryRowContext(ctx, `SELECT m.payload->'experience_outcome' FROM messages m JOIN conversations cv ON cv.id=m.conversation_id WHERE m.id=$1 AND cv.user_id=$2 AND cv.companion_id=$3 AND m.source='experience_outcome'`, id, userID, companionID).Scan(&raw)
	if err != nil {
		return nil, err
	}
	var outcome experienceOutcome
	if err = json.Unmarshal([]byte(raw), &outcome); err != nil {
		return nil, err
	}
	return &outcome, nil
}

func GetExperienceOutcome(c *gin.Context) {
	id, err := outcomeIdentity(c.Query("event_id"), c.Query("spend_id"))
	if err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	outcome, err := readExperienceOutcome(c.Request.Context(), c.GetString("user_id"), c.Param("id"), id)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(200, gin.H{"outcome": nil})
		return
	}
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to load shared keepsake"})
		return
	}
	c.JSON(200, gin.H{"outcome": outcome})
}

// Confirmation commits the actual joint choice, its card and its memory in one
// transaction. The deterministic outcome ID allows one outcome per experience.
func ConfirmExperienceOutcome(c *gin.Context) {
	ctx := c.Request.Context()
	userID, companionID := c.GetString("user_id"), c.Param("id")
	var input experienceOutcomeInput
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(400, gin.H{"error": "invalid confirmation"})
		return
	}
	input.Title = strings.TrimSpace(input.Title)
	id, err := outcomeIdentity(input.EventID, input.SpendID)
	if err != nil || input.ProposalMessageID == "" || len(input.ProposalMessageID) > 128 || utf8.RuneCountInString(input.Title) > 80 {
		c.JSON(400, gin.H{"error": "invalid confirmation"})
		return
	}
	if outcome, err := readExperienceOutcome(ctx, userID, companionID, id); err == nil {
		c.JSON(200, gin.H{"outcome": outcome})
		return
	} else if !errors.Is(err, sql.ErrNoRows) {
		c.JSON(500, gin.H{"error": "failed to load shared keepsake"})
		return
	}
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to confirm choice"})
		return
	}
	defer tx.Rollback()
	// Serialize confirmation of different drafts for the same experience.
	if _, err = tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, id); err != nil {
		c.JSON(500, gin.H{"error": "failed to lock confirmation"})
		return
	}
	var existing string
	err = tx.QueryRowContext(ctx, `SELECT m.payload->'experience_outcome' FROM messages m JOIN conversations cv ON cv.id=m.conversation_id WHERE m.id=$1 AND cv.user_id=$2 AND cv.companion_id=$3 AND m.source='experience_outcome'`, id, userID, companionID).Scan(&existing)
	if err == nil {
		var outcome experienceOutcome
		if json.Unmarshal([]byte(existing), &outcome) != nil {
			c.JSON(500, gin.H{"error": "invalid saved keepsake"})
			return
		}
		c.JSON(200, gin.H{"outcome": outcome})
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		c.JSON(500, gin.H{"error": "failed to read confirmation"})
		return
	}
	var conversationID, raw string
	err = tx.QueryRowContext(ctx, `SELECT m.conversation_id,m.payload->'experience_proposal' FROM messages m JOIN conversations cv ON cv.id=m.conversation_id WHERE m.id=$1 AND cv.user_id=$2 AND cv.companion_id=$3 AND m.sender_type='assistant' AND m.source='reply' AND m.payload->'experience_proposal' IS NOT NULL AND CASE WHEN $5<>'' THEN m.payload->>'shared_experience_spend_id'=$5 ELSE m.life_event_id=$4 END`, input.ProposalMessageID, userID, companionID, input.EventID, input.SpendID).Scan(&conversationID, &raw)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(409, gin.H{"error": "proposal is unavailable", "code": "experience_proposal_unavailable"})
		} else {
			c.JSON(500, gin.H{"error": "failed to read proposal"})
		}
		return
	}
	var outcome experienceOutcome
	if json.Unmarshal([]byte(raw), &outcome) != nil || strings.TrimSpace(outcome.Title) == "" || strings.TrimSpace(outcome.Challenge) == "" || strings.TrimSpace(outcome.Decision) == "" || strings.TrimSpace(outcome.Note) == "" {
		c.JSON(409, gin.H{"error": "invalid proposal"})
		return
	}
	var allowed bool
	if input.EventID != "" {
		err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM life_events e JOIN companions cp ON cp.id=e.companion_id JOIN companion_moment_sessions session ON session.event_id=e.id WHERE e.id=$1 AND cp.id=$2 AND cp.user_id=$3 AND e.event_type='shared_activity' AND e.generation_source='user_purchase' AND session.user_id=$3 AND session.opening_message_id IS NOT NULL AND e.start_time<=CURRENT_TIMESTAMP AND e.end_time>CURRENT_TIMESTAMP AND EXISTS(SELECT 1 FROM credit_spends paid WHERE paid.user_id=$3 AND paid.companion_id=$2 AND paid.reference_id=e.id AND paid.reference_type='companion_experience' AND paid.status='completed'))`, input.EventID, companionID, userID).Scan(&allowed)
	} else {
		err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM credit_spends WHERE id=$1 AND companion_id=$2 AND user_id=$3 AND status='completed' AND reference_type='companion_experience')`, input.SpendID, companionID, userID).Scan(&allowed)
	}
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to check shared experience"})
		return
	}
	if !allowed {
		c.JSON(409, gin.H{"error": "experience cannot confirm this choice", "code": "experience_confirmation_unavailable"})
		return
	}
	// Do not confirm a stale proposal after the user changed the discussion.
	var latest string
	err = tx.QueryRowContext(ctx, `SELECT id FROM messages WHERE conversation_id=$1 AND source IN ('user','reply') AND CASE WHEN $3<>'' THEN payload->>'shared_experience_spend_id'=$3 ELSE life_event_id=$2 END ORDER BY created_at DESC,id DESC LIMIT 1`, conversationID, input.EventID, input.SpendID).Scan(&latest)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to check latest proposal"})
		return
	}
	if latest != input.ProposalMessageID {
		c.JSON(409, gin.H{"error": "the conversation changed; review the latest proposal", "code": "experience_proposal_changed"})
		return
	}
	var turns int
	err = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM (SELECT id FROM messages WHERE conversation_id=$1 AND sender_type='user' AND CASE WHEN $3<>'' THEN payload->>'shared_experience_spend_id'=$3 ELSE life_event_id=$2 END LIMIT 2) choices`, conversationID, input.EventID, input.SpendID).Scan(&turns)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to check shared decisions"})
		return
	}
	if turns < 2 {
		c.JSON(409, gin.H{"error": "discuss the choice together first"})
		return
	}
	if input.Title != "" {
		outcome.Title = input.Title
	}
	outcome.MemoryID = id + ":memory"
	outcome.EventID = input.EventID
	outcome.SpendID = input.SpendID
	outcome.ProposalMessageID = input.ProposalMessageID
	payload, _ := json.Marshal(map[string]any{"experience_outcome": outcome, "shared_experience_spend_id": input.SpendID, "interaction_stage": "keepsake"})
	// This records a confirmed virtual experience, never a real physical meeting
	// or a permanent user preference inferred from a single decision.
	memory := fmt.Sprintf("Confirmed in-app shared experience %q. Situation: %s. The companion proposed and the user explicitly confirmed this joint decision: %s. Companion's note: %s. This was one virtual experience; do not infer lasting preferences or a real-world meeting.", outcome.Title, outcome.Challenge, outcome.Decision, outcome.Note)
	if _, err = tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,life_event_id,delivery_status) VALUES($1,$2,'assistant','text',$3,$4,'experience_outcome',NULLIF($5,''),'delivered')`, id, conversationID, outcome.Note, string(payload), input.EventID); err != nil {
		c.JSON(500, gin.H{"error": "failed to save shared keepsake"})
		return
	}
	metadata, _ := json.Marshal(map[string]any{"source": "confirmed_experience", "event_id": input.EventID, "spend_id": input.SpendID, "outcome": outcome, "completed": true})
	if _, err = tx.ExecContext(ctx, `INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata,source_message_id) VALUES($1,$2,'shared_experience',$3,90,CURRENT_TIMESTAMP,$4,$5)`, outcome.MemoryID, companionID, memory, string(metadata), id); err != nil {
		c.JSON(500, gin.H{"error": "failed to save shared memory"})
		return
	}
	if err = tx.Commit(); err != nil {
		c.JSON(500, gin.H{"error": "confirmation could not be verified"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"outcome": outcome})
}

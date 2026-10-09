package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

type companionMoment struct {
	ID            string    `json:"id"`
	ProductKey    string    `json:"product_key"`
	TitleKey      string    `json:"title_key"`
	Description   string    `json:"description_key"`
	Location      string    `json:"location"`
	StartsAt      time.Time `json:"starts_at"`
	EndsAt        time.Time `json:"ends_at"`
	Artifact      string    `json:"artifact"`
	UserText      string    `json:"user_text"`
	CompanionText string    `json:"companion_text"`
	Invitation    string    `json:"invitation"`
	Opening       string    `json:"opening"`
}

func loadCompanionMoment(ctx context.Context, userID, companionID, eventID string) (companionMoment, error) {
	var moment companionMoment
	err := db.Get().QueryRowContext(ctx, `SELECT e.id,COALESCE(e.payload->>'product_key',''),
		COALESCE(e.title,''),COALESCE(e.description,''),COALESCE(e.location,''),e.start_time,e.end_time,
		COALESCE(s.artifact_text,''),COALESCE(s.artifact_user_text,''),COALESCE(s.artifact_companion_text,''),
		COALESCE((SELECT invitation.content FROM messages invitation WHERE invitation.life_event_id=e.id AND invitation.source='moment_invitation' ORDER BY invitation.created_at DESC LIMIT 1),''),
		COALESCE(m.content,'')
		FROM life_events e JOIN companions c ON c.id=e.companion_id
		LEFT JOIN companion_moment_sessions s ON s.event_id=e.id AND s.user_id=$1
		LEFT JOIN messages m ON m.id=s.opening_message_id
		WHERE e.id=$3 AND e.companion_id=$2 AND c.user_id=$1 AND c.active=true
		AND e.event_type='shared_activity' AND e.generation_source='user_purchase'`,
		userID, companionID, eventID).Scan(&moment.ID, &moment.ProductKey, &moment.TitleKey,
		&moment.Description, &moment.Location, &moment.StartsAt, &moment.EndsAt,
		&moment.Artifact, &moment.UserText, &moment.CompanionText, &moment.Invitation, &moment.Opening)
	return moment, err
}

func GetCompanionMoment(c *gin.Context) {
	moment, err := loadCompanionMoment(c.Request.Context(), c.GetString("user_id"), c.Param("id"), c.Param("event_id"))
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "moment not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load moment"})
		return
	}
	c.JSON(http.StatusOK, moment)
}

// StartCompanionMoment is deliberately gated by the purchased event's time.
// Its opening is created once and retained in the conversation for later visits.
func StartCompanionMoment(c *gin.Context) {
	ctx := c.Request.Context()
	userID, companionID, eventID := c.GetString("user_id"), c.Param("id"), c.Param("event_id")
	moment, err := loadCompanionMoment(ctx, userID, companionID, eventID)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "moment not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load moment"})
		return
	}
	if time.Now().Before(moment.StartsAt) {
		c.JSON(http.StatusConflict, gin.H{"error": "moment has not started", "code": "moment_scheduled", "starts_at": moment.StartsAt})
		return
	}
	if !time.Now().Before(moment.EndsAt) {
		c.JSON(http.StatusConflict, gin.H{"error": "moment has ended", "code": "moment_ended"})
		return
	}
	if !requireExperienceAccess(c, userID, companionID) {
		return
	}
	if moment.Opening != "" {
		c.JSON(http.StatusOK, moment)
		return
	}
	_, _ = db.Get().ExecContext(ctx, `DELETE FROM companion_moment_sessions
		WHERE event_id=$1 AND opening_message_id IS NULL AND created_at<CURRENT_TIMESTAMP-INTERVAL '2 minutes'`, eventID)
	claim, err := db.Get().ExecContext(ctx, `INSERT INTO companion_moment_sessions(event_id,user_id,companion_id)
		VALUES($1,$2,$3) ON CONFLICT(event_id) DO NOTHING`, eventID, userID, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start moment"})
		return
	}
	claimed, _ := claim.RowsAffected()
	if claimed == 0 {
		moment, err = loadCompanionMoment(ctx, userID, companionID, eventID)
		if err == nil && moment.Opening != "" {
			c.JSON(http.StatusOK, moment)
		} else {
			c.JSON(http.StatusConflict, gin.H{"error": "moment is opening", "code": "moment_starting"})
		}
		return
	}
	completed := false
	defer func() {
		if !completed {
			cleanupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_, _ = db.Get().ExecContext(cleanupCtx, `DELETE FROM companion_moment_sessions
				WHERE event_id=$1 AND opening_message_id IS NULL`, eventID)
		}
	}()
	if companionAgent == nil {
		_, _ = db.Get().ExecContext(ctx, `DELETE FROM companion_moment_sessions WHERE event_id=$1 AND opening_message_id IS NULL`, eventID)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "agent service is unavailable"})
		return
	}
	conversationID, err := experienceConversation(ctx, userID, companionID)
	if err != nil {
		_, _ = db.Get().ExecContext(ctx, `DELETE FROM companion_moment_sessions WHERE event_id=$1 AND opening_message_id IS NULL`, eventID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to open conversation"})
		return
	}
	openingCtx, cancel := context.WithTimeout(ctx, 50*time.Second)
	defer cancel()
	text, err := companionAgent.ComposeMomentOpening(openingCtx, conversationID, userID, moment.TitleKey, moment.Location)
	if err != nil || strings.TrimSpace(text) == "" {
		_, _ = db.Get().ExecContext(context.Background(), `DELETE FROM companion_moment_sessions WHERE event_id=$1 AND opening_message_id IS NULL`, eventID)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "companion could not start the moment"})
		return
	}
	messageID := uuid.New().String()
	messagePayload, _ := json.Marshal(map[string]any{"event_id": eventID})
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save opening"})
		return
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,life_event_id,delivery_status)
		VALUES($1,$2,'assistant','text',$3,$4,'moment_opening',$5,'delivered')`, messageID, conversationID, text, messagePayload, eventID); err == nil {
		_, err = tx.ExecContext(ctx, `UPDATE companion_moment_sessions SET opening_message_id=$2 WHERE event_id=$1 AND user_id=$3`, eventID, messageID, userID)
	}
	if err != nil || tx.Commit() != nil {
		_ = tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save opening"})
		return
	}
	completed = true
	moment.Opening = text
	c.JSON(http.StatusOK, moment)
}

type momentArtifactRequest struct {
	Text string `json:"text" binding:"required"`
}

func SaveCompanionMomentArtifact(c *gin.Context) {
	ctx := c.Request.Context()
	userID, companionID, eventID := c.GetString("user_id"), c.Param("id"), c.Param("event_id")
	moment, err := loadCompanionMoment(ctx, userID, companionID, eventID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "moment not found"})
		return
	}
	var input momentArtifactRequest
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Text) == "" || len([]rune(input.Text)) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "artifact must contain 1 to 500 characters"})
		return
	}
	if time.Now().Before(moment.StartsAt) {
		c.JSON(http.StatusConflict, gin.H{"error": "moment has not started"})
		return
	}
	if !requireExperienceAccess(c, userID, companionID) {
		return
	}
	content := strings.TrimSpace(input.Text)
	if companionAgent == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "agent service is unavailable"})
		return
	}
	conversationID, err := experienceConversation(ctx, userID, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to open conversation"})
		return
	}
	composeCtx, cancel := context.WithTimeout(ctx, 50*time.Second)
	defer cancel()
	companionText, err := companionAgent.ComposeMomentArtifact(composeCtx, conversationID, userID, moment.TitleKey, content)
	if err != nil || strings.TrimSpace(companionText) == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "companion could not add to the memory"})
		return
	}
	jointText := content + " · " + strings.TrimSpace(companionText)
	metadata, _ := json.Marshal(map[string]any{"event_id": eventID, "co_created": true})
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save artifact"})
		return
	}
	defer tx.Rollback()
	var previous string
	if err = tx.QueryRowContext(ctx, `SELECT artifact_text FROM companion_moment_sessions WHERE event_id=$1 AND user_id=$2 FOR UPDATE`, eventID, userID).Scan(&previous); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "open the moment before saving"})
		return
	}
	if _, err = tx.ExecContext(ctx, `UPDATE companion_moment_sessions SET artifact_text=$2,artifact_user_text=$3,
		artifact_companion_text=$4,artifact_updated_at=CURRENT_TIMESTAMP WHERE event_id=$1`, eventID, jointText, content, companionText); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save artifact"})
		return
	}
	if previous == "" {
		_, err = tx.ExecContext(ctx, `INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata)
			VALUES($1,$2,'shared_creation',$3,85,CURRENT_TIMESTAMP,$4)`, uuid.New().String(), companionID, jointText, string(metadata))
	} else {
		var updated sql.Result
		updated, err = tx.ExecContext(ctx, `UPDATE memories SET content=$3 WHERE companion_id=$1 AND type='shared_creation' AND metadata LIKE $2`, companionID, "%"+eventID+"%", jointText)
		if err == nil {
			count, countErr := updated.RowsAffected()
			if countErr != nil {
				err = countErr
			} else if count == 0 {
				_, err = tx.ExecContext(ctx, `INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata)
					VALUES($1,$2,'shared_creation',$3,85,CURRENT_TIMESTAMP,$4)`, uuid.New().String(), companionID, jointText, string(metadata))
			}
		}
	}
	if err != nil || tx.Commit() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save artifact"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"artifact": jointText, "user_text": content, "companion_text": companionText})
}

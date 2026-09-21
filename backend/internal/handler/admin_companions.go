package handler

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"vita/internal/config"
	"vita/internal/db"
)

// AdminListManagedCompanions returns user-created companions for the dedicated
// moderation screen. System default companions remain managed in Agent config.
func AdminListManagedCompanions(c *gin.Context) {
	page, pageSize := adminPage(c)
	conds := []string{"c.is_default=false"}
	args := make([]any, 0, 4)
	if q := strings.TrimSpace(c.Query("q")); q != "" {
		args = append(args, "%"+q+"%")
		conds = append(conds, fmt.Sprintf("(c.name ILIKE $%d OR u.email ILIKE $%d)", len(args), len(args)))
	}
	if userID := strings.TrimSpace(c.Query("user_id")); userID != "" {
		args = append(args, userID)
		conds = append(conds, fmt.Sprintf("c.user_id=$%d", len(args)))
	}
	if status := strings.TrimSpace(c.Query("status")); status == "active" || status == "inactive" {
		args = append(args, status == "active")
		conds = append(conds, fmt.Sprintf("c.active=$%d", len(args)))
	}
	if env := strings.TrimSpace(c.Query("environment")); env != "" {
		if !config.IsValidEnvironment(env) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "environment must be dev, beta, or prod"})
			return
		}
		args = append(args, env)
		conds = append(conds, fmt.Sprintf("u.environment=$%d", len(args)))
	}
	where := " WHERE " + strings.Join(conds, " AND ")
	var total int
	if err := db.Get().QueryRow(`SELECT COUNT(*) FROM companions c JOIN users u ON u.id=c.user_id`+where, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to count companions"})
		return
	}
	args = append(args, pageSize, (page-1)*pageSize)
	query := `SELECT c.id,c.user_id,u.email,u.environment,c.name,COALESCE(c.gender,''),COALESCE(c.city,''),
		COALESCE(c.occupation,''),COALESCE(c.relationship_stage,'stranger'),c.active,c.proactive_enabled,
		c.voice_enabled,COALESCE(NULLIF(c.avatar_url,''),p.image_url,''),COUNT(DISTINCT cv.id),COUNT(DISTINCT m.id),c.created_at,c.updated_at
		FROM companions c JOIN users u ON u.id=c.user_id
		LEFT JOIN companion_portraits p ON p.id=c.portrait_id
		LEFT JOIN conversations cv ON cv.companion_id=c.id
		LEFT JOIN messages m ON m.conversation_id=cv.id` + where + `
		GROUP BY c.id,u.email,u.environment,p.image_url
		ORDER BY c.created_at DESC LIMIT $` + strconv.Itoa(len(args)-1) + ` OFFSET $` + strconv.Itoa(len(args))
	rows, err := db.Get().Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list companions"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, userID, email, environment, name, gender, city, occupation, stage, portraitURL string
		var active, proactive, voice bool
		var conversations, messages int
		var created, updated time.Time
		if err := rows.Scan(&id, &userID, &email, &environment, &name, &gender, &city, &occupation, &stage, &active, &proactive, &voice, &portraitURL, &conversations, &messages, &created, &updated); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read companions"})
			return
		}
		items = append(items, gin.H{"id": id, "user_id": userID, "user_email": email, "environment": environment, "name": name, "gender": gender, "city": city, "occupation": occupation, "relationship_stage": stage, "active": active, "proactive_enabled": proactive, "voice_enabled": voice, "portrait_url": portraitURL, "conversations": conversations, "messages": messages, "created_at": created, "updated_at": updated})
	}
	totalPages := 0
	if total > 0 {
		totalPages = (total + pageSize - 1) / pageSize
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "total": total, "page": page, "page_size": pageSize, "total_pages": totalPages})
}

func AdminGetManagedCompanion(c *gin.Context) {
	var item struct {
		ID, UserID, UserEmail, Environment, Name, Gender, Persona, City, Occupation, Interests string
		RelationshipStage, SpeakingStyle, Likes, Dislikes, LifeHabits, LifeGoal, Backstory     string
		CreationSource, PortraitURL, ModelName                                                 string
		Tags, VoiceConfig                                                                      json.RawMessage
		ModelID, PortraitID                                                                    sql.NullString
		Proactive, Active, LifeEnabled, FriendshipActive, VoiceEnabled                         bool
		PausedAt                                                                               sql.NullTime
		CreatedAt, UpdatedAt                                                                   time.Time
		Conversations, Messages, Memories, LifeEvents                                          int
		Mood, Energy, Stress, SocialEnergy, Intimacy, Trust, Familiarity, Enthusiasm           int
	}
	err := db.Get().QueryRow(`SELECT c.id,c.user_id,u.email,u.environment,c.name,COALESCE(c.gender,''),COALESCE(c.persona,''),
		COALESCE(c.city,''),COALESCE(c.occupation,''),COALESCE(c.interests,''),COALESCE(c.relationship_stage,'stranger'),
		c.personality_tags::text,c.speaking_style,c.likes,c.dislikes,c.life_habits,c.life_goal,c.backstory,c.model_id,c.portrait_id,
		c.creation_source,c.proactive_enabled,c.active,c.life_enabled,c.friendship_active,c.subscription_paused_at,c.voice_enabled,
		c.voice_config::text,COALESCE(NULLIF(c.avatar_url,''),p.image_url,''),COALESCE(am.display_name,''),c.created_at,c.updated_at,
		(SELECT COUNT(*) FROM conversations WHERE companion_id=c.id),
		(SELECT COUNT(*) FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE companion_id=c.id)),
		(SELECT COUNT(*) FROM memories WHERE companion_id=c.id),(SELECT COUNT(*) FROM life_events WHERE companion_id=c.id),
		COALESCE(cs.mood,50),COALESCE(cs.energy,50),COALESCE(cs.stress,50),COALESCE(cs.social_energy,50),
		COALESCE(rs.intimacy,0),COALESCE(rs.trust,0),COALESCE(rs.familiarity,0),COALESCE(rs.enthusiasm,0)
		FROM companions c JOIN users u ON u.id=c.user_id
		LEFT JOIN companion_portraits p ON p.id=c.portrait_id LEFT JOIN ai_models am ON am.id=c.model_id
		LEFT JOIN companion_states cs ON cs.companion_id=c.id LEFT JOIN relationship_states rs ON rs.companion_id=c.id
		WHERE c.id=$1 AND c.is_default=false`, c.Param("id")).Scan(
		&item.ID, &item.UserID, &item.UserEmail, &item.Environment, &item.Name, &item.Gender, &item.Persona,
		&item.City, &item.Occupation, &item.Interests, &item.RelationshipStage, &item.Tags, &item.SpeakingStyle,
		&item.Likes, &item.Dislikes, &item.LifeHabits, &item.LifeGoal, &item.Backstory, &item.ModelID, &item.PortraitID,
		&item.CreationSource, &item.Proactive, &item.Active, &item.LifeEnabled, &item.FriendshipActive, &item.PausedAt,
		&item.VoiceEnabled, &item.VoiceConfig, &item.PortraitURL, &item.ModelName, &item.CreatedAt, &item.UpdatedAt,
		&item.Conversations, &item.Messages, &item.Memories, &item.LifeEvents, &item.Mood, &item.Energy, &item.Stress,
		&item.SocialEnergy, &item.Intimacy, &item.Trust, &item.Familiarity, &item.Enthusiasm)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"id": item.ID, "user_id": item.UserID, "user_email": item.UserEmail, "environment": item.Environment,
		"name": item.Name, "gender": item.Gender, "persona": item.Persona, "city": item.City, "occupation": item.Occupation,
		"interests": item.Interests, "relationship_stage": item.RelationshipStage, "personality_tags": item.Tags,
		"speaking_style": item.SpeakingStyle, "likes": item.Likes, "dislikes": item.Dislikes, "life_habits": item.LifeHabits,
		"life_goal": item.LifeGoal, "backstory": item.Backstory, "model_id": nullString(item.ModelID), "model_name": item.ModelName,
		"portrait_id": nullString(item.PortraitID), "portrait_url": item.PortraitURL, "creation_source": item.CreationSource,
		"proactive_enabled": item.Proactive, "active": item.Active, "life_enabled": item.LifeEnabled,
		"friendship_active": item.FriendshipActive, "subscription_paused_at": nullTime(item.PausedAt),
		"voice_enabled": item.VoiceEnabled, "voice_config": item.VoiceConfig, "created_at": item.CreatedAt, "updated_at": item.UpdatedAt,
		"conversations": item.Conversations, "messages": item.Messages, "memories": item.Memories, "life_events": item.LifeEvents,
		"state":        gin.H{"mood": item.Mood, "energy": item.Energy, "stress": item.Stress, "social_energy": item.SocialEnergy},
		"relationship": gin.H{"intimacy": item.Intimacy, "trust": item.Trust, "familiarity": item.Familiarity, "enthusiasm": item.Enthusiasm},
	})
}

func AdminUpdateManagedCompanion(c *gin.Context) {
	var exists bool
	if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM companions WHERE id=$1 AND is_default=false)`, c.Param("id")).Scan(&exists); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion"})
		return
	}
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	saveAdminCompanion(c, c.Param("id"))
}

func AdminListCompanionConversations(c *gin.Context) {
	rows, err := db.Get().Query(`SELECT cv.id,cv.user_id,cv.companion_id,cv.created_at,cv.updated_at,
		COUNT(m.id),COALESCE((SELECT content FROM messages WHERE conversation_id=cv.id ORDER BY created_at DESC LIMIT 1),''),MAX(m.created_at)
		FROM conversations cv JOIN companions c ON c.id=cv.companion_id LEFT JOIN messages m ON m.conversation_id=cv.id
		WHERE cv.companion_id=$1 AND c.is_default=false GROUP BY cv.id ORDER BY MAX(m.created_at) DESC NULLS LAST,cv.updated_at DESC`, c.Param("id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list conversations"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, userID, companionID, lastMessage string
		var created, updated time.Time
		var lastMessageAt sql.NullTime
		var count int
		if err := rows.Scan(&id, &userID, &companionID, &created, &updated, &count, &lastMessage, &lastMessageAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read conversations"})
			return
		}
		items = append(items, gin.H{"id": id, "user_id": userID, "companion_id": companionID, "message_count": count, "last_message": lastMessage, "last_message_at": nullTime(lastMessageAt), "created_at": created, "updated_at": updated})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminListConversationMessages(c *gin.Context) {
	page, pageSize := adminPage(c)
	companionID, conversationID := c.Param("id"), c.Param("conversation_id")
	var total int
	err := db.Get().QueryRow(`SELECT COUNT(*) FROM messages m JOIN conversations cv ON cv.id=m.conversation_id WHERE cv.id=$1 AND cv.companion_id=$2`, conversationID, companionID).Scan(&total)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to count messages"})
		return
	}
	rows, err := db.Get().Query(`SELECT m.id,m.conversation_id,m.sender_type,m.message_type,COALESCE(m.content,''),COALESCE(m.media_url,''),m.payload::text,m.source,COALESCE(m.life_event_id,''),m.delivery_status,m.created_at
		FROM messages m JOIN conversations cv ON cv.id=m.conversation_id WHERE cv.id=$1 AND cv.companion_id=$2
		ORDER BY m.created_at DESC LIMIT $3 OFFSET $4`, conversationID, companionID, pageSize, (page-1)*pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list messages"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, cvID, sender, messageType, content, mediaURL, payload, source, lifeEventID, delivery string
		var created time.Time
		if err := rows.Scan(&id, &cvID, &sender, &messageType, &content, &mediaURL, &payload, &source, &lifeEventID, &delivery, &created); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read messages"})
			return
		}
		items = append(items, gin.H{"id": id, "conversation_id": cvID, "sender_type": sender, "message_type": messageType, "content": content, "media_url": mediaURL, "payload": json.RawMessage(payload), "source": source, "life_event_id": lifeEventID, "delivery_status": delivery, "created_at": created})
	}
	totalPages := 0
	if total > 0 {
		totalPages = (total + pageSize - 1) / pageSize
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "total": total, "page": page, "page_size": pageSize, "total_pages": totalPages})
}

func AdminDeleteManagedCompanion(c *gin.Context) {
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete companion"})
		return
	}
	defer tx.Rollback()
	id := c.Param("id")
	var isDefault bool
	if err = tx.QueryRow(`SELECT is_default FROM companions WHERE id=$1 FOR UPDATE`, id).Scan(&isDefault); errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete companion"})
		return
	}
	if isDefault {
		c.JSON(http.StatusBadRequest, gin.H{"error": "system default companions cannot be deleted here"})
		return
	}
	statements := []string{
		`DELETE FROM notification_outbox WHERE companion_id=$1`,
		`DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE companion_id=$1)`,
		`DELETE FROM conversations WHERE companion_id=$1`,
		`DELETE FROM memories WHERE companion_id=$1`,
		`DELETE FROM life_events WHERE companion_id=$1`,
		`DELETE FROM relationship_states WHERE companion_id=$1`,
		`DELETE FROM companion_states WHERE companion_id=$1`,
		`DELETE FROM companion_days WHERE companion_id=$1`,
		`DELETE FROM companion_gifts WHERE companion_id=$1`,
		`DELETE FROM companions WHERE id=$1`,
	}
	for _, statement := range statements {
		if _, err = tx.ExecContext(c.Request.Context(), statement, id); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete companion"})
			return
		}
	}
	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete companion"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "companion deleted"})
}

package handler

import (
	"database/sql"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

func ListEncounterConversations(c *gin.Context) {
	rows, err := db.Get().QueryContext(c.Request.Context(), `SELECT v.id,r.name,r.avatar_url,r.cover_url,r.id,
 COALESCE(latest.content,''),latest.created_at,COALESCE(unread.count,0)
 FROM encounter_conversations v JOIN encounter_characters r ON r.id=v.character_id
 LEFT JOIN LATERAL(SELECT m.content,m.created_at FROM encounter_messages m WHERE m.conversation_id=v.id
  ORDER BY m.created_at DESC,m.id DESC LIMIT 1) latest ON true
 LEFT JOIN LATERAL(SELECT COUNT(*) AS count FROM encounter_messages m WHERE m.conversation_id=v.id
  AND m.sender_type='assistant' AND (m.created_at,m.id)>(v.last_read_at,v.last_read_message_id)) unread ON true
 WHERE v.user_id=$1 ORDER BY (COALESCE(unread.count,0)>0) DESC,latest.created_at DESC NULLS LAST,v.updated_at DESC,v.id`, c.GetString("user_id"))
	if err != nil {
		c.JSON(500, gin.H{"error": "cannot load conversations"})
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id, name, avatar, cover, charID, preview string
		var at sql.NullTime
		var unread int
		if err := rows.Scan(&id, &name, &avatar, &cover, &charID, &preview, &at, &unread); err != nil {
			c.JSON(500, gin.H{"error": "cannot read conversations"})
			return
		}
		var lastAt *time.Time
		if at.Valid {
			value := at.Time
			lastAt = &value
		}
		items = append(items, gin.H{"id": id, "name": name, "avatar_url": avatar, "cover_url": cover, "character_id": charID,
			"last_message": preview, "last_message_at": lastAt, "unread_count": unread})
	}
	if rows.Err() != nil {
		c.JSON(500, gin.H{"error": "cannot read conversations"})
		return
	}
	c.JSON(200, gin.H{"items": items})
}

func ReadEncounterConversation(c *gin.Context) {
	if !encounterOwned(c) {
		return
	}
	var input struct {
		MessageID string `json:"message_id"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(400, gin.H{"error": "invalid read marker"})
		return
	}
	if _, err := uuid.Parse(input.MessageID); err != nil {
		c.JSON(400, gin.H{"error": "invalid message id"})
		return
	}
	// A server-owned message cursor cannot acknowledge a newer, unseen arrival.
	_, err := db.Get().ExecContext(c.Request.Context(), `UPDATE encounter_conversations v
 SET last_read_at=m.created_at,last_read_message_id=m.id FROM encounter_messages m
 WHERE v.id=$1 AND v.user_id=$2 AND m.id=$3 AND m.conversation_id=v.id AND m.sender_type='assistant'
 AND (m.created_at,m.id)>(v.last_read_at,v.last_read_message_id)`, c.Param("id"), c.GetString("user_id"), input.MessageID)
	if err != nil {
		c.JSON(500, gin.H{"error": "cannot mark conversation read"})
		return
	}
	c.Status(204)
}

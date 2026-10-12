package handler

import (
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"vita/internal/db"
)

// CompanionUpdates returns changed message summaries only. The cursor is a
// client snapshot, not an authorization token; all rows remain user-scoped.
func CompanionUpdates(c *gin.Context) {
	previous := map[string]string{}
	cursor := c.Query("cursor")
	if len(cursor) > 65536 {
		c.JSON(400, gin.H{"error": "invalid cursor"})
		return
	}
	if cursor != "" {
		raw, err := base64.RawURLEncoding.DecodeString(cursor)
		if err != nil || json.Unmarshal(raw, &previous) != nil {
			c.JSON(400, gin.H{"error": "invalid cursor"})
			return
		}
	}
	rows, err := db.Get().QueryContext(c.Request.Context(), `SELECT c.id,
 COALESCE(latest.content,''),COALESCE(latest.message_type,'text'),latest.created_at,COALESCE(unread.count,0)
 FROM companions c
 LEFT JOIN LATERAL (
 SELECT m.content,m.message_type,m.created_at FROM conversations cv JOIN messages m ON m.conversation_id=cv.id
 WHERE cv.user_id=$1 AND cv.companion_id=c.id ORDER BY m.created_at DESC,m.id DESC LIMIT 1
 ) latest ON true
 LEFT JOIN LATERAL (
 SELECT COUNT(*) AS count FROM conversations cv JOIN messages m ON m.conversation_id=cv.id
 WHERE cv.user_id=$1 AND cv.companion_id=c.id AND m.sender_type='assistant'
 AND m.created_at>COALESCE(cv.last_read_at,cv.created_at)
 ) unread ON true
 WHERE c.user_id=$1 AND c.active=true AND COALESCE(c.creation_source,'')<>'ai_pet'
 ORDER BY c.id`, c.GetString("user_id"))
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to load notification updates"})
		return
	}
	defer rows.Close()
	current := map[string]string{}
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, content, messageType string
		var at sql.NullTime
		var unread int
		if err := rows.Scan(&id, &content, &messageType, &at, &unread); err != nil {
			c.JSON(500, gin.H{"error": "failed to read notification updates"})
			return
		}
		item := gin.H{"id": id, "last_message": content, "last_message_type": messageType, "last_message_at": nullTime(at), "unread_count": unread}
		raw, _ := json.Marshal(item)
		revision := fmt.Sprintf("%x", sha256.Sum256(raw))
		current[id] = revision
		if previous[id] != revision {
			items = append(items, item)
		}
	}
	if rows.Err() != nil {
		c.JSON(500, gin.H{"error": "failed to read notification updates"})
		return
	}
	removed := make([]string, 0)
	for id := range previous {
		if _, exists := current[id]; !exists {
			removed = append(removed, id)
		}
	}
	raw, _ := json.Marshal(current)
	c.JSON(http.StatusOK, gin.H{"items": items, "removed_ids": removed, "cursor": base64.RawURLEncoding.EncodeToString(raw)})
}

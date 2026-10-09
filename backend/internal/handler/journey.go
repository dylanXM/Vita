package handler

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"vita/internal/db"
)

// GetJourney returns a user's memories and keepsakes across active companions.
func GetJourney(c *gin.Context) {
	limit := 30
	if raw := c.Query("limit"); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 1 || value > 50 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid limit"})
			return
		}
		limit = value
	}
	offset := 0
	if raw := c.Query("offset"); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 0 || value > 10000 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid offset"})
			return
		}
		offset = value
	}
	companionID := strings.TrimSpace(c.Query("companion_id"))
	query := strings.TrimSpace(c.Query("q"))
	if len(query) > 100 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "query is too long"})
		return
	}
	rows, err := db.Get().QueryContext(c.Request.Context(), `
		SELECT j.id,j.kind,j.title,j.content,j.occurred_at,j.readonly,
			c.id,c.name,COALESCE(NULLIF(c.avatar_url,''),p.image_url,'')
		FROM (
			SELECT m.id,COALESCE(m.type,'memory') AS kind,'' AS title,
				COALESCE(m.content,'') AS content,
				COALESCE(m.event_time,m.created_at,CURRENT_TIMESTAMP::timestamp) AS occurred_at,
				false AS readonly,m.companion_id
			FROM memories m
			UNION ALL
			SELECT k.id,'keepsake' AS kind,k.title,k.content,k.created_at AS occurred_at,
				true AS readonly,k.companion_id
			FROM companion_keepsakes k
		) j
		JOIN companions c ON c.id=j.companion_id
		LEFT JOIN companion_portraits p ON p.id=c.portrait_id
		WHERE c.user_id=$1 AND c.active=true AND c.deleted_at IS NULL
			AND COALESCE(c.creation_source,'')<>'ai_pet'
			AND ($2='' OR c.id=$2)
			AND ($3='' OR c.name ILIKE '%' || $3 || '%'
				OR j.title ILIKE '%' || $3 || '%'
				OR j.content ILIKE '%' || $3 || '%')
		ORDER BY j.occurred_at DESC,j.id DESC
		LIMIT $4 OFFSET $5`, c.GetString("user_id"), companionID, query, limit+1, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load journey"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0, limit)
	for rows.Next() {
		var id, kind, title, content, actorID, actorName, avatar string
		var occurredAt time.Time
		var readonly bool
		if err := rows.Scan(&id, &kind, &title, &content, &occurredAt, &readonly,
			&actorID, &actorName, &avatar); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read journey"})
			return
		}
		items = append(items, gin.H{
			"id": id, "type": kind, "title": title, "content": content,
			"event_time": occurredAt, "readonly": readonly,
			"companion": gin.H{"id": actorID, "name": actorName, "portrait_url": avatar},
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read journey"})
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "has_more": hasMore, "next_offset": offset + len(items)})
}

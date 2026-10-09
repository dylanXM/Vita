package handler

import (
	"database/sql"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"vita/internal/db"
)

// GetCompanionStory joins records the user can already access into a single
// chronology. Chat content is deliberately excluded; only its first date is
// used. A generated life event is shown only after it has been shared.
func GetCompanionStory(c *gin.Context) {
	companionID, userID := c.Param("id"), c.GetString("user_id")
	var createdAt time.Time
	var relationshipStage string
	err := db.Get().QueryRowContext(c.Request.Context(),
		`SELECT created_at,COALESCE(relationship_stage,'stranger') FROM companions WHERE id=$1 AND user_id=$2`,
		companionID, userID).Scan(&createdAt, &relationshipStage)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion story"})
		return
	}

	rows, err := db.Get().QueryContext(c.Request.Context(), `
		SELECT kind,id,title,description,occurred_at,source,is_favorite FROM (
			SELECT 'memory' AS kind,m.id,'' AS title,COALESCE(m.content,'') AS description,
				COALESCE(m.event_time,m.created_at) AS occurred_at,COALESCE(m.type,'') AS source,m.is_favorite
			FROM memories m WHERE m.companion_id=$1 AND COALESCE(m.content,'')<>''
			UNION ALL
			SELECT 'event',e.id,COALESCE(e.title,''),COALESCE(e.description,''),e.start_time,
				COALESCE(e.generation_source,''),false
			FROM life_events e WHERE e.companion_id=$1 AND e.status='active'
				AND (e.shared_at IS NOT NULL OR
					(e.generation_source='user_purchase' AND e.end_time<=CURRENT_TIMESTAMP))
				AND e.start_time IS NOT NULL
			UNION ALL
			SELECT 'first_chat',c.id,'','',MIN(m.created_at),'',false
			FROM conversations c JOIN messages m ON m.conversation_id=c.id
			WHERE c.companion_id=$1 AND c.user_id=$2 AND m.created_at IS NOT NULL GROUP BY c.id
		) story ORDER BY occurred_at DESC LIMIT 40`, companionID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion story"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var kind, id, title, description, source string
		var occurredAt time.Time
		var favorite bool
		if err := rows.Scan(&kind, &id, &title, &description, &occurredAt, &source, &favorite); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read companion story"})
			return
		}
		items = append(items, gin.H{"kind": kind, "id": id, "title": title,
			"description": description, "occurred_at": occurredAt,
			"source": source, "is_favorite": favorite})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read companion story"})
		return
	}
	spentRows, err := db.Get().QueryContext(c.Request.Context(), `SELECT DISTINCT product_key FROM credit_spends
		WHERE user_id=$1 AND companion_id=$2 AND reference_type='companion_experience' AND status='completed'`, userID, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load shared experiences"})
		return
	}
	defer spentRows.Close()
	experiencedKeys := make([]string, 0)
	for spentRows.Next() {
		var key string
		if err := spentRows.Scan(&key); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read shared experiences"})
			return
		}
		experiencedKeys = append(experiencedKeys, key)
	}
	if err := spentRows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read shared experiences"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"created_at": createdAt, "relationship_stage": relationshipStage,
		"experienced_keys": experiencedKeys, "items": items})
}

func SetMemoryFavorite(c *gin.Context) {
	var input struct {
		Favorite *bool `json:"favorite"`
	}
	if err := c.ShouldBindJSON(&input); err != nil || input.Favorite == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "favorite is required"})
		return
	}
	result, err := db.Get().ExecContext(c.Request.Context(), `UPDATE memories m SET is_favorite=$1
		FROM companions c WHERE m.id=$2 AND m.companion_id=$3 AND c.id=m.companion_id AND c.user_id=$4`,
		*input.Favorite, c.Param("memory_id"), c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save favorite"})
		return
	}
	count, err := result.RowsAffected()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify favorite"})
		return
	}
	if count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "memory not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": c.Param("memory_id"), "is_favorite": *input.Favorite})
}

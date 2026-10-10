package handler

import (
	"encoding/json"
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
		SELECT j.id,j.kind,j.title,j.content,j.occurred_at,j.readonly,j.metadata,
			c.id,c.name,COALESCE(NULLIF(c.avatar_url,''),p.image_url,'')
		FROM (
			SELECT m.id,COALESCE(m.type,'memory') AS kind,'' AS title,
				COALESCE(m.content,'') AS content,
				COALESCE(m.event_time,m.created_at,CURRENT_TIMESTAMP::timestamp) AS occurred_at,
				false AS readonly,m.companion_id,COALESCE(NULLIF(m.metadata::text,''),'{}')::jsonb AS metadata
			FROM memories m
			WHERE (m.type<>'shared_experience'
				OR COALESCE(COALESCE(NULLIF(m.metadata::text,''),'{}')::jsonb->>'paid_experience','false')<>'true'
				OR COALESCE(COALESCE(NULLIF(m.metadata::text,''),'{}')::jsonb->>'event_id','')='')
				AND m.type IS DISTINCT FROM 'world_visit'
			UNION ALL
			SELECT w.id,'world_visit' AS kind,'' AS title,
				COALESCE(NULLIF(w.payload->>'reaction',''),
					CASE WHEN w.payload->>'choice'='ask' THEN 'The user asked about my day during a visit.'
					ELSE 'The user stayed with me during a visit.' END) AS content,
				w.created_at AS occurred_at,true AS readonly,w.companion_id,
				w.payload || jsonb_build_object('follow_up',COALESCE((
					SELECT msg.content FROM messages msg
					WHERE msg.source='memory_followup' AND msg.payload->>'memory_id'=visit_memory.id
					ORDER BY msg.created_at DESC LIMIT 1
				),'')) AS metadata
			FROM world_interactions w
			LEFT JOIN LATERAL (
				SELECT m.id FROM memories m
				WHERE m.companion_id=w.companion_id AND m.type='world_visit'
					AND m.event_time BETWEEN w.created_at-INTERVAL '2 minutes' AND w.created_at+INTERVAL '2 minutes'
					AND COALESCE(NULLIF(m.metadata,''),'{}')::jsonb->>'choice'=w.payload->>'choice'
					AND COALESCE(NULLIF(m.metadata,''),'{}')::jsonb->>'source_event_id'=w.payload->>'source_event_id'
				ORDER BY ABS(EXTRACT(EPOCH FROM (m.event_time-w.created_at))) LIMIT 1
			) visit_memory ON true
			WHERE w.user_id=$1 AND w.kind='visit'
			UNION ALL
			SELECT k.id,'keepsake' AS kind,k.title,k.content,k.created_at AS occurred_at,
				true AS readonly,k.companion_id,COALESCE(k.payload,'{}'::jsonb) AS metadata
			FROM companion_keepsakes k
			UNION ALL
			SELECT e.id,CASE WHEN COALESCE(s.closing_text,'')<>'' THEN 'shared_experience'
				ELSE 'experience_appointment' END AS kind,COALESCE(e.title,'') AS title,
				CASE WHEN COALESCE(s.closing_text,'')<>'' THEN s.closing_text
					WHEN COALESCE(opening.content,'')<>'' THEN opening.content
					ELSE COALESCE(invitation.content,'') END AS content,
				CASE WHEN COALESCE(s.closing_text,'')<>'' THEN e.end_time ELSE e.start_time END AS occurred_at,
				true AS readonly,e.companion_id,
				jsonb_build_object('event_id',e.id,'stage',
					CASE WHEN COALESCE(s.closing_text,'')<>'' THEN 'finished'
						WHEN s.opening_message_id IS NOT NULL THEN 'active'
						ELSE 'booked' END,
					'starts_at',e.start_time,'preparation_choice',COALESCE(e.payload->>'preparation_choice','')) AS metadata
			FROM life_events e
			LEFT JOIN companion_moment_sessions s ON s.event_id=e.id AND s.user_id=$1
			LEFT JOIN messages opening ON opening.id=s.opening_message_id
			LEFT JOIN LATERAL (SELECT content FROM messages WHERE life_event_id=e.id AND source='moment_invitation'
				ORDER BY created_at DESC LIMIT 1) invitation ON true
			WHERE e.event_type='shared_activity' AND e.generation_source='user_purchase'
				AND e.status<>'cancelled'
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
		var metadataJSON []byte
		var occurredAt time.Time
		var readonly bool
		if err := rows.Scan(&id, &kind, &title, &content, &occurredAt, &readonly, &metadataJSON,
			&actorID, &actorName, &avatar); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read journey"})
			return
		}
		metadata := map[string]any{}
		if len(metadataJSON) > 0 {
			if err := json.Unmarshal(metadataJSON, &metadata); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read journey metadata"})
				return
			}
		}
		content = publicTransferMemoryContent(kind, content, metadata)
		if kind == "kind_gesture" && metadata["transfer_id"] != nil && content != "" {
			metadata["reply"] = content
		}
		items = append(items, gin.H{
			"id": id, "type": kind, "title": title, "content": content,
			"event_time": occurredAt, "readonly": readonly, "metadata": metadata,
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

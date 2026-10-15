package handler

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"vita/internal/db"
)

// ListChatAppointments returns the nearest paid, unfinished date per companion.
func ListChatAppointments(c *gin.Context) {
	rows, err := db.Get().QueryContext(c.Request.Context(), `
 SELECT a.id,a.companion_id,a.title,a.start_time,a.end_time,a.started
 FROM (
  SELECT DISTINCT ON (e.companion_id) e.id,e.companion_id,COALESCE(e.title,'') AS title,
   e.start_time,e.end_time,ms.opening_message_id IS NOT NULL AS started
  FROM life_events e
  JOIN companions companion ON companion.id=e.companion_id
  LEFT JOIN companion_moment_sessions ms ON ms.event_id=e.id AND ms.user_id=$1
  WHERE companion.user_id=$1 AND companion.active=true AND companion.deleted_at IS NULL
   AND COALESCE(companion.creation_source,'')<>'ai_pet'
   AND e.event_type='shared_activity' AND e.generation_source='user_purchase'
   AND e.status IN ('active','scheduled') AND e.end_time>CURRENT_TIMESTAMP
   AND COALESCE(ms.closing_text,'')=''
   AND EXISTS(SELECT 1 FROM credit_spends paid WHERE paid.user_id=$1
    AND paid.companion_id=e.companion_id AND paid.reference_id=e.id
    AND paid.status='completed' AND paid.reference_type='companion_experience')
  ORDER BY e.companion_id,e.start_time,e.id
 ) a ORDER BY a.start_time,a.id`, c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load appointments"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, companionID, title string
		var startsAt, endsAt time.Time
		var started bool
		if err := rows.Scan(&id, &companionID, &title, &startsAt, &endsAt, &started); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read appointments"})
			return
		}
		items = append(items, gin.H{"id": id, "companion_id": companionID,
			"title_key": title, "starts_at": startsAt, "ends_at": endsAt, "started": started})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read appointments"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

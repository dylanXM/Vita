package handler

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

const maxAnalyticsBatch = 50
const maxAnalyticsPropertiesBytes = 16 * 1024

type analyticsEventInput struct {
	EventID     string         `json:"event_id"`
	Name        string         `json:"name"`
	Category    string         `json:"category"`
	AnonymousID string         `json:"anonymous_id"`
	SessionID   string         `json:"session_id"`
	Timestamp   string         `json:"timestamp"`
	Properties  map[string]any `json:"properties"`
}

type analyticsBatchInput struct {
	Events []analyticsEventInput `json:"events"`
}

func IngestAnalyticsEvents(c *gin.Context) {
	var input analyticsBatchInput
	if err := c.ShouldBindJSON(&input); err != nil || len(input.Events) == 0 || len(input.Events) > maxAnalyticsBatch {
		c.JSON(http.StatusBadRequest, gin.H{"error": "events must contain between 1 and 50 items"})
		return
	}
	userID := c.GetString("user_id")
	platform := normalizeMobilePlatform(c.GetHeader("X-Vita-Platform"))
	appVersion := strings.TrimSpace(c.GetHeader("X-Vita-App-Version"))
	locale := strings.TrimSpace(c.GetHeader("Accept-Language"))
	accepted := 0
	for _, event := range input.Events {
		name := strings.TrimSpace(event.Name)
		anonymousID := strings.TrimSpace(event.AnonymousID)
		if !validAnalyticsName(name) || anonymousID == "" || (userID == "" && !anonymousAnalyticsAllowed(name)) {
			continue
		}
		properties, err := json.Marshal(event.Properties)
		if err != nil || len(properties) > maxAnalyticsPropertiesBytes {
			continue
		}
		eventID := strings.TrimSpace(event.EventID)
		if eventID == "" {
			eventID = uuid.NewString()
		}
		var clientAt *time.Time
		if parsed, err := time.Parse(time.RFC3339Nano, event.Timestamp); err == nil {
			utc := parsed.UTC()
			clientAt = &utc
		}
		result, err := db.Get().Exec(`INSERT INTO analytics_events
			(id,user_id,anonymous_id,session_id,event_name,category,properties,platform,environment,app_version,locale,client_at)
			VALUES($1,NULLIF($2,''),$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
			ON CONFLICT(id) DO NOTHING`, eventID, userID, anonymousID, strings.TrimSpace(event.SessionID), name,
			normalizeAnalyticsCategory(event.Category, name), properties, platform, currentEnvironment(), appVersion, locale, clientAt)
		if err != nil {
			continue
		}
		if rows, _ := result.RowsAffected(); rows > 0 {
			accepted++
		}
		if userID != "" {
			_, _ = db.Get().Exec(`UPDATE analytics_events SET user_id=$1 WHERE anonymous_id=$2 AND user_id IS NULL`, userID, anonymousID)
		}
	}
	c.JSON(http.StatusOK, gin.H{"accepted": accepted})
}

func validAnalyticsName(value string) bool {
	if len(value) < 2 || len(value) > 80 {
		return false
	}
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '.' {
			continue
		}
		return false
	}
	return true
}

func anonymousAnalyticsAllowed(name string) bool {
	return name == "app_started" || name == "screen_view" || strings.HasPrefix(name, "onboarding_") || strings.HasPrefix(name, "auth_")
}

func normalizeAnalyticsCategory(category, name string) string {
	category = strings.ToLower(strings.TrimSpace(category))
	valid := map[string]bool{"navigation": true, "auth": true, "onboarding": true, "chat": true, "companion": true, "billing": true, "life": true, "profile": true, "updates": true, "system": true, "general": true}
	if valid[category] {
		return category
	}
	for prefix, candidate := range map[string]string{
		"screen_": "navigation", "tab_": "navigation", "auth_": "auth", "onboarding_": "onboarding", "chat_": "chat", "message_": "chat",
		"companion_": "companion", "purchase_": "billing", "subscription_": "billing", "credits_": "billing", "gift_": "billing",
		"life_": "life", "memory_": "life", "profile_": "profile", "whats_new_": "updates",
	} {
		if strings.HasPrefix(name, prefix) {
			return candidate
		}
	}
	return "general"
}

type userTimelineItem struct {
	ID         string          `json:"id"`
	EventName  string          `json:"event_name"`
	Category   string          `json:"category"`
	Source     string          `json:"source"`
	Properties json.RawMessage `json:"properties"`
	Platform   string          `json:"platform"`
	AppVersion string          `json:"app_version"`
	SessionID  string          `json:"session_id"`
	OccurredAt time.Time       `json:"occurred_at"`
}

const userTimelineSQL = `WITH timeline AS (
	SELECT id,event_name,category,'app'::text AS source,properties,platform,app_version,session_id,COALESCE(client_at,created_at) AS occurred_at
	FROM analytics_events WHERE user_id=$1
	UNION ALL
	SELECT 'account:'||id,'account_registered','auth','system',jsonb_build_object('environment',environment),'system','','',created_at FROM users WHERE id=$1
	UNION ALL
	SELECT 'companion:'||id,'companion_created','companion','system',jsonb_build_object('companion_id',id,'name',name,'creation_source',creation_source),'system','','',created_at FROM companions WHERE user_id=$1
	UNION ALL
	SELECT 'message:'||m.id,'message_sent','chat','system',jsonb_build_object('message_id',m.id,'conversation_id',m.conversation_id,'companion_id',c.companion_id,'message_type',m.message_type),'system','','',m.created_at
	FROM messages m JOIN conversations c ON c.id=m.conversation_id WHERE c.user_id=$1 AND m.sender_type='user'
	UNION ALL
	SELECT 'credit:'||id,'credits_changed','billing','system',jsonb_build_object('amount',amount,'balance_after',balance_after,'kind',kind,'description',COALESCE(description,'')),'system','','',created_at FROM credit_transactions WHERE user_id=$1
	UNION ALL
	SELECT 'purchase:'||id,'purchase_recorded','billing','system',jsonb_build_object('kind',kind,'provider',provider,'product_id',product_id,'credits',credits,'status',status,'currency',currency,'amount_minor',amount_minor),platform,'','',purchased_at FROM billing_purchases WHERE user_id=$1
	UNION ALL
	SELECT 'gift:'||id,'gift_sent','billing','system',jsonb_build_object('companion_id',companion_id,'coins',coins,'intimacy_delta',intimacy_delta,'enthusiasm_delta',enthusiasm_delta),'system','','',created_at FROM companion_gifts WHERE user_id=$1
) `

func AdminUserTimeline(c *gin.Context) {
	limit := 30
	if parsed, err := strconv.Atoi(c.Query("limit")); err == nil && parsed > 0 {
		limit = min(parsed, 100)
	}
	offset := 0
	if parsed, err := strconv.Atoi(c.Query("offset")); err == nil && parsed > 0 {
		offset = parsed
	}
	category := strings.ToLower(strings.TrimSpace(c.Query("category")))
	query := userTimelineSQL + `SELECT id,event_name,category,source,properties,platform,app_version,session_id,occurred_at,COUNT(*) OVER() AS total
		FROM timeline WHERE ($2='' OR category=$2) ORDER BY occurred_at DESC,id DESC LIMIT $3 OFFSET $4`
	rows, err := db.Get().Query(query, c.Param("id"), category, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user timeline"})
		return
	}
	defer rows.Close()
	items := make([]userTimelineItem, 0)
	total := 0
	for rows.Next() {
		var item userTimelineItem
		if err := rows.Scan(&item.ID, &item.EventName, &item.Category, &item.Source, &item.Properties, &item.Platform, &item.AppVersion, &item.SessionID, &item.OccurredAt, &total); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read user timeline"})
			return
		}
		items = append(items, item)
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "total": total, "limit": limit, "offset": offset})
}

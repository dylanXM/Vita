package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/credits"
	"vita/internal/db"
)

type companionGiftRequest struct {
	Coins int `json:"coins" binding:"required,min=1,max=100000"`
}

func TransferCoinsToCompanion(c *gin.Context) {
	userID := c.GetString("user_id")
	companionID := c.Param("id")
	var input companionGiftRequest
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	active, err := userHasActiveSubscription(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check subscription"})
		return
	}
	if !active {
		subscriptionRequired(c, "gift_requires_subscription", "Subscribe to reconnect before sending a gift")
		return
	}
	var exists bool
	if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM companions WHERE id=$1 AND user_id=$2 AND active=true AND is_default=false)`, companionID, userID).Scan(&exists); err != nil || !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	legacyProductKey := map[int]string{10: "legacy_gift_10", 50: "legacy_gift_50", 100: "legacy_gift_100"}[input.Coins]
	if legacyProductKey == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "this legacy gift amount is no longer available", "code": "product_unavailable"})
		return
	}
	idempotencyKey := strings.TrimSpace(c.GetHeader("X-Idempotency-Key"))
	if idempotencyKey == "" {
		idempotencyKey = "legacy-gift-" + uuid.New().String()
	}
	reservation, err := credits.Reserve(c.Request.Context(), db.Get(), credits.ReserveParams{
		UserID: userID, CompanionID: companionID, Environment: currentEnvironment(), Platform: requestPlatform(c),
		ProductKey: legacyProductKey, IdempotencyKey: idempotencyKey, ReferenceType: "legacy_gift",
	})
	if err != nil {
		writeSpendError(c, err)
		return
	}
	if reservation.Idempotent {
		c.JSON(http.StatusOK, gin.H{"balance": reservation.Balance, "coins": reservation.Product.Coins, "result": reservation.Result, "idempotent": true})
		return
	}
	result, referenceID, err := fulfillCatalogGift(c.Request.Context(), userID, companionID, reservation.Product)
	if err != nil {
		settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = credits.Refund(settlementCtx, db.Get(), reservation.ID, err.Error())
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to send gift", "refunded": true})
		return
	}
	settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := credits.Complete(settlementCtx, db.Get(), reservation.ID, referenceID, result); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "gift completed but settlement could not be recorded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"balance": reservation.Balance, "coins": reservation.Product.Coins, "result": result})
}

func userHasActiveSubscription(userID string) (bool, error) {
	var active bool
	err := db.Get().QueryRow(`SELECT EXISTS(
		SELECT 1 FROM subscriptions WHERE user_id=$1 AND status='active'
		AND (current_period_end IS NULL OR current_period_end > CURRENT_TIMESTAMP)
	)`, userID).Scan(&active)
	return active, err
}

func subscriptionRequired(c *gin.Context, code, message string) {
	c.JSON(402, gin.H{"error": message, "code": code, "action": "open_subscription"})
}

func ensureDefaultCompanions(userID string) error {
	if _, err := db.Get().Exec(`UPDATE companions SET active=false,updated_at=CURRENT_TIMESTAMP
		WHERE user_id=$1 AND is_default=true AND portrait_id NOT IN
		(SELECT id FROM companion_portraits WHERE enabled=true AND is_default=true)`, userID); err != nil {
		return err
	}
	rows, err := db.Get().Query(`SELECT id,name,gender,personality_tags::text
		FROM companion_portraits WHERE enabled=true AND is_default=true ORDER BY sort_order,name`)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var portraitID, name, gender, tags string
		if err := rows.Scan(&portraitID, &name, &gender, &tags); err != nil {
			return err
		}
		companionID := uuid.New().String()
		_, err = db.Get().Exec(`UPDATE companions SET name=$3,gender=$4,personality_tags=$5,
			active=true,updated_at=CURRENT_TIMESTAMP WHERE user_id=$1 AND portrait_id=$2 AND is_default=true`,
			userID, portraitID, name, gender, tags)
		if err != nil {
			return err
		}
		_, err = db.Get().Exec(`INSERT INTO companions
			(id,user_id,name,gender,persona,relationship_stage,personality_tags,portrait_id,creation_source,
			 proactive_enabled,active,is_default,life_enabled,friendship_active)
			VALUES ($1,$2,$3,$4,$5,'acquaintance',$6,$7,'system_default',false,true,true,false,true)
			ON CONFLICT DO NOTHING`, companionID, userID, name,
			gender, "A welcoming default Vita companion available during the free chat experience.", tags, portraitID)
		if err != nil {
			return err
		}
		_, _ = db.Get().Exec(`INSERT INTO relationship_states (companion_id) SELECT $1
			WHERE EXISTS(SELECT 1 FROM companions WHERE id=$1) ON CONFLICT DO NOTHING`, companionID)
	}
	return rows.Err()
}

func defaultChatAccess(userID string, startTrial bool) (bool, *time.Time, error) {
	subscribed, err := userHasActiveSubscription(userID)
	if err != nil || subscribed {
		return subscribed, nil, err
	}
	var expires time.Time
	err = db.Get().QueryRow(`SELECT expires_at FROM default_companion_trials WHERE user_id=$1`, userID).Scan(&expires)
	if err == nil {
		return time.Now().Before(expires), &expires, nil
	}
	if err == sql.ErrNoRows && !startTrial {
		return true, nil, nil
	}
	if err != sql.ErrNoRows {
		return false, nil, err
	}
	var hours int
	if err := db.Get().QueryRow(`SELECT free_default_chat_hours FROM agent_settings WHERE id='default'`).Scan(&hours); err != nil {
		return false, nil, err
	}
	if hours < 1 {
		hours = 1
	}
	expires = time.Now().Add(time.Duration(hours) * time.Hour)
	if _, err = db.Get().Exec(`INSERT INTO default_companion_trials(user_id,expires_at) VALUES($1,$2)
		ON CONFLICT(user_id) DO NOTHING`, userID, expires); err != nil {
		return false, nil, err
	}
	// A second device may start the same trial concurrently. Always read back
	// the persisted deadline so every device observes the same window.
	if err = db.Get().QueryRow(`SELECT expires_at FROM default_companion_trials WHERE user_id=$1`, userID).Scan(&expires); err != nil {
		return false, nil, err
	}
	return time.Now().Before(expires), &expires, nil
}

func decorateCompanionAccess(userID string, companion *Companion) {
	if companion.IsDefault {
		allowed, expires, _ := defaultChatAccess(userID, false)
		companion.CanChat = allowed
		companion.RequiresSubscription = !allowed
		companion.TrialExpiresAt = expires
		return
	}
	active, _ := userHasActiveSubscription(userID)
	companion.CanChat = active
	companion.FriendshipActive = active && companion.FriendshipActive
	companion.RequiresSubscription = !active
}

func requireCompanionLifeAccess(c *gin.Context, companionID string) bool {
	userID := c.GetString("user_id")
	var isDefault bool
	if err := db.Get().QueryRow(`SELECT is_default FROM companions WHERE id=$1 AND user_id=$2 AND active=true`, companionID, userID).Scan(&isDefault); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return false
	}
	active, err := userHasActiveSubscription(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check subscription"})
		return false
	}
	if isDefault || !active {
		subscriptionRequired(c, "life_engine_requires_subscription", "Subscribe to unlock your companion's life")
		return false
	}
	return true
}

func syncUserCompanionEntitlement(userID string, active bool) error {
	if !active {
		_, err := db.Get().Exec(`UPDATE companions SET life_enabled=false,friendship_active=false,
			subscription_paused_at=COALESCE(subscription_paused_at,CURRENT_TIMESTAMP),updated_at=CURRENT_TIMESTAMP
			WHERE user_id=$1 AND is_default=false AND (active=true OR deleted_at IS NOT NULL)`, userID)
		return err
	}

	tx, err := db.Get().Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	// Lock paused companions while producing catch-up records. Subscription
	// refreshes and provider webhooks can arrive together; the lock makes the
	// resume summary exactly-once for each paused interval.
	rows, err := tx.Query(`SELECT id,name,subscription_paused_at FROM companions
		WHERE user_id=$1 AND active=true AND is_default=false AND subscription_paused_at IS NOT NULL
		FOR UPDATE`, userID)
	if err != nil {
		return err
	}
	type pausedCompanion struct {
		id, name string
		pausedAt time.Time
	}
	var paused []pausedCompanion
	for rows.Next() {
		var item pausedCompanion
		if err := rows.Scan(&item.id, &item.name, &item.pausedAt); err != nil {
			rows.Close()
			return err
		}
		paused = append(paused, item)
	}
	if err := rows.Close(); err != nil {
		return err
	}

	for _, item := range paused {
		days := max(1, int(time.Since(item.pausedAt).Hours()/24))
		summary := fmt.Sprintf("我们失去联系的这 %d 天里，我继续过着自己的生活：工作、休息，也有一些平常但值得记住的小变化。现在重新联系上你了。", days)
		eventID := uuid.New().String()
		payload, _ := json.Marshal(map[string]any{"from": item.pausedAt, "to": time.Now(), "days": days})
		_, err = tx.Exec(`INSERT INTO life_events
			(id,companion_id,event_type,title,description,start_time,end_time,emotion,importance,user_relevance,
			 shareability,status,payload,generation_source,created_at)
			VALUES($1,$2,'catch_up_summary','这段时间的生活', $3,$4,$5,'reflective',60,80,false,'active',$6,'subscription_resume',CURRENT_TIMESTAMP)`,
			eventID, item.id, summary, item.pausedAt, time.Now(), string(payload))
		if err != nil {
			return err
		}
		var conversationID string
		err = tx.QueryRow(`SELECT id FROM conversations WHERE user_id=$1 AND companion_id=$2 LIMIT 1`, userID, item.id).Scan(&conversationID)
		if err == sql.ErrNoRows {
			conversationID = uuid.New().String()
			_, err = tx.Exec(`INSERT INTO conversations(id,user_id,companion_id) VALUES($1,$2,$3)`, conversationID, userID, item.id)
		}
		if err != nil {
			return err
		}
		_, err = tx.Exec(`INSERT INTO messages
			(id,conversation_id,sender_type,message_type,content,payload,source,life_event_id,delivery_status)
			VALUES($1,$2,'assistant','text',$3,$4,'subscription_resume',$5,'delivered')`,
			uuid.New().String(), conversationID, summary, string(payload), eventID)
		if err != nil {
			return err
		}
	}
	_, err = tx.Exec(`UPDATE companions SET life_enabled=true,friendship_active=true,
		subscription_paused_at=NULL,updated_at=CURRENT_TIMESTAMP
		WHERE user_id=$1 AND active=true AND is_default=false AND deleted_at IS NULL`, userID)
	if err != nil {
		return err
	}
	_, err = tx.Exec(`UPDATE companions SET life_enabled=true,friendship_active=false,proactive_enabled=false,
		subscription_paused_at=NULL,updated_at=CURRENT_TIMESTAMP
		WHERE user_id=$1 AND deleted_at IS NOT NULL AND purge_after>CURRENT_TIMESTAMP AND is_default=false`, userID)
	if err != nil {
		return err
	}
	return tx.Commit()
}

package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/credits"
	"vita/internal/db"
)

type experienceRequest struct {
	IdempotencyKey string         `json:"idempotency_key" binding:"required"`
	Input          map[string]any `json:"input"`
}

func ListCompanionExperiences(c *gin.Context) {
	userID := c.GetString("user_id")
	companionID := c.Param("id")
	if !requireExperienceAccess(c, userID, companionID) {
		return
	}
	products, err := credits.ListProducts(c.Request.Context(), db.Get(), currentEnvironment(), c.Query("category"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load experiences"})
		return
	}
	var balance int
	_ = db.Get().QueryRow(`SELECT credits_balance FROM users WHERE id=$1`, userID).Scan(&balance)
	owned := map[string]bool{}
	rows, err := db.Get().Query(`SELECT product_key FROM companion_outfits WHERE user_id=$1 AND companion_id=$2`, userID, companionID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var key string
			if rows.Scan(&key) == nil {
				owned[key] = true
			}
		}
	}
	var equipped string
	_ = db.Get().QueryRow(`SELECT equipped_outfit_key FROM companions WHERE id=$1 AND user_id=$2`, companionID, userID).Scan(&equipped)
	c.JSON(http.StatusOK, gin.H{"balance": balance, "products": products, "owned_outfits": owned, "equipped_outfit": equipped})
}

func PurchaseCompanionExperience(c *gin.Context) {
	ctx := c.Request.Context()
	userID := c.GetString("user_id")
	companionID := c.Param("id")
	productKey := strings.TrimSpace(c.Param("product_key"))
	if !requireExperienceAccess(c, userID, companionID) {
		return
	}
	var input experienceRequest
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "idempotency_key is required", "code": "invalid_request"})
		return
	}
	if strings.HasPrefix(productKey, "outfit_") {
		var owned bool
		_ = db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM companion_outfits WHERE user_id=$1 AND companion_id=$2 AND product_key=$3)`, userID, companionID, productKey).Scan(&owned)
		if owned {
			if _, err := db.Get().Exec(`UPDATE companions SET equipped_outfit_key=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2`, companionID, userID, productKey); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to equip outfit"})
				return
			}
			var balance int
			_ = db.Get().QueryRow(`SELECT credits_balance FROM users WHERE id=$1`, userID).Scan(&balance)
			c.JSON(http.StatusOK, gin.H{"balance": balance, "product_key": productKey, "equipped": true, "already_owned": true})
			return
		}
	}

	reservation, err := credits.Reserve(ctx, db.Get(), credits.ReserveParams{
		UserID: userID, CompanionID: companionID, Environment: currentEnvironment(), Platform: requestPlatform(c),
		ProductKey: productKey, IdempotencyKey: input.IdempotencyKey, ReferenceType: "companion_experience", Metadata: input.Input,
	})
	if err != nil {
		writeSpendError(c, err)
		return
	}
	if reservation.Idempotent {
		c.JSON(http.StatusOK, gin.H{"balance": reservation.Balance, "product": reservation.Product, "result": reservation.Result, "idempotent": true})
		return
	}

	result, referenceID, err := fulfillExperience(ctx, userID, companionID, reservation.Product)
	if err != nil {
		settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if refundErr := credits.Refund(settlementCtx, db.Get(), reservation.ID, err.Error()); refundErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "experience failed and refund could not be confirmed", "code": "refund_unconfirmed"})
			return
		}
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": err.Error(), "code": "experience_failed", "refunded": true})
		return
	}
	result["spend_id"] = reservation.ID
	result["product_key"] = reservation.Product.Key
	result["coins"] = reservation.Product.Coins
	settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := credits.Complete(settlementCtx, db.Get(), reservation.ID, referenceID, result); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "experience completed but settlement could not be recorded", "code": "settlement_pending"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"balance": reservation.Balance, "product": reservation.Product, "result": result})
}

func fulfillExperience(ctx context.Context, userID, companionID string, product credits.Product) (map[string]any, string, error) {
	switch product.Category {
	case "gift":
		return fulfillCatalogGift(ctx, userID, companionID, product)
	case "photo":
		if companionAgent == nil {
			return nil, "", fmt.Errorf("agent service is unavailable")
		}
		message, err := companionAgent.GenerateRequestedLifePhoto(ctx, userID, companionID)
		if err != nil {
			return nil, "", err
		}
		return map[string]any{"message": message}, message.ID, nil
	case "voice":
		if companionAgent == nil {
			return nil, "", fmt.Errorf("agent service is unavailable")
		}
		message, err := companionAgent.SpeakLatestReply(ctx, userID, companionID)
		if err != nil {
			return nil, "", err
		}
		return map[string]any{"message": message}, message.ID, nil
	case "date":
		return fulfillVirtualDate(ctx, userID, companionID, product)
	case "keepsake":
		return fulfillKeepsake(ctx, userID, companionID, product)
	case "outfit":
		return fulfillOutfit(ctx, userID, companionID, product)
	case "call":
		return nil, "", fmt.Errorf("real-time calling is not configured")
	default:
		return nil, "", fmt.Errorf("unsupported experience")
	}
}

func fulfillCatalogGift(ctx context.Context, userID, companionID string, product credits.Product) (map[string]any, string, error) {
	intimacy := metadataInt(product.Metadata, "intimacy", 1)
	enthusiasm := metadataInt(product.Metadata, "enthusiasm", 2)
	id := uuid.New().String()
	conversationID, err := experienceConversation(ctx, userID, companionID)
	if err != nil {
		return nil, "", err
	}
	messageID := uuid.New().String()
	createdAt := time.Now().UTC()
	messageData := map[string]any{
		"product_key": product.Key,
		"gift_id":     id,
		"name_key":    product.NameKey,
		"emoji":       product.Emoji,
		"coins":       product.Coins,
	}
	messagePayload, _ := json.Marshal(messageData)
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		return nil, "", err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `INSERT INTO companion_gifts(id,user_id,companion_id,coins,intimacy_delta,enthusiasm_delta,product_key)
		VALUES($1,$2,$3,$4,$5,$6,$7)`, id, userID, companionID, product.Coins, intimacy, enthusiasm, product.Key); err != nil {
		return nil, "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO relationship_states(companion_id,intimacy,trust,familiarity,enthusiasm)
		VALUES($1,$2,1,1,$3) ON CONFLICT(companion_id) DO UPDATE SET
		intimacy=LEAST(100,relationship_states.intimacy+$2),trust=LEAST(100,relationship_states.trust+1),
		familiarity=LEAST(100,relationship_states.familiarity+1),enthusiasm=LEAST(100,relationship_states.enthusiasm+$3),updated_at=CURRENT_TIMESTAMP`, companionID, intimacy, enthusiasm); err != nil {
		return nil, "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,delivery_status,created_at)
		VALUES($1,$2,'user','gift',$3,$4,'paid_gift','delivered',$5)`, messageID, conversationID, product.Emoji, messagePayload, createdAt); err != nil {
		return nil, "", err
	}
	if err := tx.Commit(); err != nil {
		return nil, "", err
	}
	message := map[string]any{
		"id": messageID, "conversation_id": conversationID,
		"sender_type": "user", "message_type": "gift",
		"content": product.Emoji, "media_url": "", "payload": messageData,
		"source": "paid_gift", "life_event_id": "",
		"delivery_status": "delivered", "created_at": createdAt,
	}
	return map[string]any{
		"gift_id": id, "message_id": messageID, "emoji": product.Emoji,
		"intimacy_delta": intimacy, "enthusiasm_delta": enthusiasm,
		"message": message,
	}, id, nil
}

func fulfillVirtualDate(ctx context.Context, userID, companionID string, product credits.Product) (map[string]any, string, error) {
	if companionAgent == nil {
		return nil, "", fmt.Errorf("agent service is unavailable")
	}
	status, err := companionAgent.CurrentStatus(ctx, companionID, userID)
	if err != nil {
		return nil, "", err
	}
	start := time.Now().UTC()
	if status.Busy && status.AvailableAt != nil && status.AvailableAt.After(start) {
		start = status.AvailableAt.Add(15 * time.Minute)
	}
	duration := time.Duration(metadataInt(product.Metadata, "duration_minutes", 60)) * time.Minute
	start, err = nextAvailableExperienceTime(ctx, companionID, start, duration)
	if err != nil {
		return nil, "", err
	}
	location, _ := product.Metadata["location"].(string)
	eventID := uuid.New().String()
	memoryID := uuid.New().String()
	payload, _ := json.Marshal(map[string]any{"paid_experience": true, "product_key": product.Key, "with_user": true})
	title := product.NameKey
	description := product.DescriptionKey
	conversationID, err := experienceConversation(ctx, userID, companionID)
	if err != nil {
		return nil, "", err
	}
	messageID := uuid.New().String()
	messagePayload, _ := json.Marshal(map[string]any{"event_id": eventID, "product_key": product.Key, "scheduled_at": start})
	var timezone string
	_ = db.Get().QueryRowContext(ctx, `SELECT timezone FROM users WHERE id=$1`, userID).Scan(&timezone)
	locationZone, zoneErr := time.LoadLocation(timezone)
	if zoneErr != nil {
		locationZone = time.UTC
	}
	localDate := start.In(locationZone).Format("2006-01-02")
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		return nil, "", err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `INSERT INTO life_events(id,companion_id,event_type,title,description,location,start_time,end_time,emotion,importance,user_relevance,shareability,status,local_date,payload,generation_source)
		VALUES($1,$2,'shared_activity',$3,$4,$5,$6,$7,'anticipating',85,100,false,'active',$8::date,$9,'user_purchase')`, eventID, companionID, title, description, location, start, start.Add(duration), localDate, payload); err != nil {
		return nil, "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata)
		VALUES($1,$2,'shared_experience',$3,80,$4,$5)`, memoryID, companionID, description, start, string(payload)); err != nil {
		return nil, "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,life_event_id,delivery_status)
		VALUES($1,$2,'assistant','scene_card',$3,$4,'paid_date',$5,'delivered')`, messageID, conversationID, description, messagePayload, eventID); err != nil {
		return nil, "", err
	}
	if err := tx.Commit(); err != nil {
		return nil, "", err
	}
	return map[string]any{"event_id": eventID, "memory_id": memoryID, "message_id": messageID, "scheduled_at": start}, eventID, nil
}

func fulfillKeepsake(ctx context.Context, userID, companionID string, product credits.Product) (map[string]any, string, error) {
	rows, err := db.Get().QueryContext(ctx, `SELECT content FROM memories WHERE companion_id=$1 ORDER BY importance DESC,created_at DESC LIMIT 3`, companionID)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()
	var memories []string
	for rows.Next() {
		var content string
		if rows.Scan(&content) == nil && strings.TrimSpace(content) != "" {
			memories = append(memories, strings.TrimSpace(content))
		}
	}
	if len(memories) == 0 {
		return nil, "", fmt.Errorf("at least one shared memory is required")
	}
	id := uuid.New().String()
	content := strings.Join(memories, " · ")
	var duplicate bool
	if err := db.Get().QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM companion_keepsakes WHERE user_id=$1 AND companion_id=$2 AND content=$3)`, userID, companionID, content).Scan(&duplicate); err != nil {
		return nil, "", err
	}
	if duplicate {
		return nil, "", fmt.Errorf("these memories already have a keepsake")
	}
	payload, _ := json.Marshal(map[string]any{"product_key": product.Key, "memory_count": len(memories)})
	if _, err := db.Get().ExecContext(ctx, `INSERT INTO companion_keepsakes(id,user_id,companion_id,title,content,payload) VALUES($1,$2,$3,$4,$5,$6)`,
		id, userID, companionID, product.NameKey, content, payload); err != nil {
		return nil, "", err
	}
	return map[string]any{"keepsake_id": id, "title_key": product.NameKey, "content": content}, id, nil
}

func fulfillOutfit(ctx context.Context, userID, companionID string, product credits.Product) (map[string]any, string, error) {
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		return nil, "", err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `INSERT INTO companion_outfits(user_id,companion_id,product_key) VALUES($1,$2,$3)`, userID, companionID, product.Key); err != nil {
		return nil, "", err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE companions SET equipped_outfit_key=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2`, companionID, userID, product.Key); err != nil {
		return nil, "", err
	}
	if err := tx.Commit(); err != nil {
		return nil, "", err
	}
	return map[string]any{"equipped": true}, product.Key, nil
}

func experienceConversation(ctx context.Context, userID, companionID string) (string, error) {
	var id string
	err := db.Get().QueryRowContext(ctx, `SELECT id FROM conversations WHERE user_id=$1 AND companion_id=$2 ORDER BY created_at LIMIT 1`, userID, companionID).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}
	id = uuid.New().String()
	_, err = db.Get().ExecContext(ctx, `INSERT INTO conversations(id,user_id,companion_id) VALUES($1,$2,$3)`, id, userID, companionID)
	return id, err
}

func nextAvailableExperienceTime(ctx context.Context, companionID string, candidate time.Time, duration time.Duration) (time.Time, error) {
	rows, err := db.Get().QueryContext(ctx, `SELECT start_time,end_time FROM life_events
		WHERE companion_id=$1 AND status='active' AND end_time>$2 AND start_time<$3
		ORDER BY start_time`, companionID, candidate, candidate.Add(36*time.Hour))
	if err != nil {
		return time.Time{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var start, end time.Time
		if err := rows.Scan(&start, &end); err != nil {
			return time.Time{}, err
		}
		if candidate.Add(duration).After(start) && candidate.Before(end) {
			candidate = end.Add(15 * time.Minute)
		}
	}
	return candidate, rows.Err()
}

func requireExperienceAccess(c *gin.Context, userID, companionID string) bool {
	var isDefault bool
	err := db.Get().QueryRow(`SELECT is_default FROM companions WHERE id=$1 AND user_id=$2 AND active=true`, companionID, userID).Scan(&isDefault)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return false
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion"})
		return false
	}
	if isDefault {
		allowed, _, err := defaultChatAccess(userID, false)
		if err != nil || !allowed {
			subscriptionRequired(c, "experience_requires_subscription", "Subscribe to continue shared experiences")
			return false
		}
		return true
	}
	active, err := userHasActiveSubscription(userID)
	if err != nil || !active {
		subscriptionRequired(c, "experience_requires_subscription", "Subscribe to continue shared experiences")
		return false
	}
	return true
}

func writeSpendError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, credits.ErrProductNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "experience is unavailable", "code": "product_unavailable"})
	case errors.Is(err, credits.ErrInsufficientCredit):
		c.JSON(http.StatusPaymentRequired, gin.H{"error": "insufficient credits", "code": "insufficient_credits", "action": "open_credits"})
	case errors.Is(err, credits.ErrSpendInProgress):
		c.JSON(http.StatusConflict, gin.H{"error": "experience is still processing", "code": "spend_in_progress"})
	case errors.Is(err, credits.ErrSpendRefunded):
		c.JSON(http.StatusConflict, gin.H{"error": "this request was already refunded", "code": "spend_refunded"})
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error(), "code": "spend_failed"})
	}
}

func metadataInt(metadata map[string]any, key string, fallback int) int {
	value, ok := metadata[key]
	if !ok {
		return fallback
	}
	switch typed := value.(type) {
	case float64:
		return int(typed)
	case int:
		return typed
	default:
		return fallback
	}
}

func AdminListCreditProducts(c *gin.Context) {
	environment := strings.TrimSpace(c.Query("environment"))
	if environment != "dev" && environment != "beta" && environment != "prod" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "environment is required"})
		return
	}
	rows, err := db.Get().Query(`SELECT product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata::text
		FROM credit_products WHERE environment=$1
		AND COALESCE((metadata->>'hidden_from_catalog')::boolean,false)=false
		ORDER BY category,sort_order,product_key`, environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load credit products"})
		return
	}
	defer rows.Close()
	items := []credits.Product{}
	for rows.Next() {
		var item credits.Product
		var raw string
		if err := rows.Scan(&item.Key, &item.Category, &item.NameKey, &item.DescriptionKey, &item.Emoji, &item.Coins, &item.Enabled, &item.SortOrder, &raw); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan credit products"})
			return
		}
		_ = json.Unmarshal([]byte(raw), &item.Metadata)
		items = append(items, item)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminUpdateCreditProduct(c *gin.Context) {
	environment := strings.TrimSpace(c.Query("environment"))
	if environment != "dev" && environment != "beta" && environment != "prod" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "environment is required"})
		return
	}
	if strings.HasPrefix(c.Param("product_key"), "legacy_gift_") {
		c.JSON(http.StatusConflict, gin.H{"error": "legacy gift products are fixed for old app compatibility"})
		return
	}
	var input struct {
		Coins     int  `json:"coins" binding:"required,min=1,max=100000"`
		Enabled   bool `json:"enabled"`
		SortOrder int  `json:"sort_order"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid credit product"})
		return
	}
	var category string
	if err := db.Get().QueryRow(`SELECT category FROM credit_products WHERE environment=$1 AND product_key=$2`, environment, c.Param("product_key")).Scan(&category); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "credit product not found"})
		return
	}
	if category == "call" && input.Enabled {
		c.JSON(http.StatusConflict, gin.H{"error": "configure a real-time calling provider before enabling call products"})
		return
	}
	result, err := db.Get().Exec(`UPDATE credit_products SET coins=$3,enabled=$4,sort_order=$5,updated_at=CURRENT_TIMESTAMP
		WHERE environment=$1 AND product_key=$2`, environment, c.Param("product_key"), input.Coins, input.Enabled, input.SortOrder)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update credit product"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "credit product not found"})
		return
	}
	AdminListCreditProducts(c)
}

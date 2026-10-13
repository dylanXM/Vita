package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/credits"
	"vita/internal/db"
	"vita/internal/language"
)

type experienceRequest struct {
	IdempotencyKey string         `json:"idempotency_key" binding:"required"`
	Input          map[string]any `json:"input"`
}

var (
	errInvalidAppointment = errors.New("choose a time from 5 minutes to 30 days ahead")
)

func ListCompanionExperiences(c *gin.Context) {
	userID := c.GetString("user_id")
	companionID := c.Param("id")
	if !requireExperienceCompanion(c, userID, companionID) {
		return
	}
	products, err := credits.ListProducts(c.Request.Context(), db.Get(), currentEnvironment(), c.Query("category"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load experiences"})
		return
	}
	subscribed, err := userHasActiveSubscription(userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to load subscription"})
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
	var name, portrait, title, location string
	if err := db.Get().QueryRowContext(c.Request.Context(), `SELECT c.name,COALESCE(NULLIF(c.avatar_url,''),p.image_url,''),COALESCE(e.title,''),COALESCE(e.location,'')
 FROM companions c LEFT JOIN companion_portraits p ON p.id=c.portrait_id
 LEFT JOIN LATERAL(SELECT title,location FROM life_events WHERE companion_id=c.id AND status='active' AND start_time<=CURRENT_TIMESTAMP AND end_time>CURRENT_TIMESTAMP ORDER BY CASE WHEN event_type='shared_activity' AND generation_source='user_purchase' THEN 0 ELSE 1 END,start_time DESC,id DESC LIMIT 1) e ON true
 WHERE c.id=$1 AND c.user_id=$2`, companionID, userID).Scan(&name, &portrait, &title, &location); err != nil {
		c.JSON(500, gin.H{"error": "failed to load experience context"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"balance": balance, "is_subscribed": subscribed, "products": products, "owned_outfits": owned, "equipped_outfit": equipped, "companion": gin.H{"name": name, "portrait_url": portrait}, "scene": gin.H{"title": title, "location": location}})
}

func PurchaseCompanionExperience(c *gin.Context) {
	ctx := c.Request.Context()
	userID := c.GetString("user_id")
	companionID := c.Param("id")
	productKey := strings.TrimSpace(c.Param("product_key"))
	if !requireExperienceCompanion(c, userID, companionID) {
		return
	}
	if !syncExperienceLocale(c) {
		return
	}
	var input experienceRequest
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "idempotency_key is required", "code": "invalid_request"})
		return
	}
	if raw, exists := input.Input["custom_request"]; exists {
		text, ok := raw.(string)
		if !ok || utf8.RuneCountInString(text) > 500 {
			c.JSON(400, gin.H{"error": "custom request must be text up to 500 characters", "code": "invalid_request"})
			return
		}
	}
	var subscriptionOnly, launched bool
	err := db.Get().QueryRowContext(ctx, `SELECT subscription_only,is_launched FROM credit_products WHERE environment=$1 AND product_key=$2 AND enabled=true`, currentEnvironment(), productKey).Scan(&subscriptionOnly, &launched)
	if errors.Is(err, sql.ErrNoRows) {
		writeSpendError(c, credits.ErrProductNotFound)
		return
	}
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to load experience"})
		return
	}
	if !launched {
		writeSpendError(c, credits.ErrNotLaunched)
		return
	}
	if subscriptionOnly {
		subscribed, err := userHasActiveSubscription(userID)
		if err != nil {
			c.JSON(500, gin.H{"error": "failed to load subscription"})
			return
		}
		if !subscribed {
			writeSpendError(c, credits.ErrSubscriptionRequired)
			return
		}
	}
	if strings.HasPrefix(productKey, "outfit_") {
		var owned bool
		_ = db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM companion_outfits WHERE user_id=$1 AND companion_id=$2 AND product_key=$3)`, userID, companionID, productKey).Scan(&owned)
		if owned {
			equipOwnedMediaOutfit(c, userID, companionID, productKey)
			return
		}
	}
	if strings.TrimSpace(input.IdempotencyKey) == "" || len(input.IdempotencyKey) > 128 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid idempotency key", "code": "invalid_request"})
		return
	}
	var productCategory string
	if err := db.Get().QueryRowContext(ctx, `SELECT category FROM credit_products WHERE environment=$1 AND product_key=$2 AND enabled=true`,
		currentEnvironment(), productKey).Scan(&productCategory); err != nil && !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load experience"})
		return
	}
	if productCategory == "date" {
		requestCompanionDate(c, userID, companionID, productKey, input)
		return
	}

	if productCategory == "photo" || productCategory == "voice" || productCategory == "outfit" {
		purchaseMediaExperience(c, userID, companionID, productKey, input)
		return
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

	result, referenceID, err := fulfillExperience(ctx, userID, companionID, reservation.Product, input.Input)
	if err != nil {
		settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if refundErr := credits.Refund(settlementCtx, db.Get(), reservation.ID, err.Error()); refundErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "experience failed and refund could not be confirmed", "code": "refund_unconfirmed"})
			return
		}
		code := "experience_failed"
		if errors.Is(err, errInvalidAppointment) {
			code = "invalid_appointment"
		}
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": err.Error(), "code": code, "refunded": true})
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

func fulfillExperience(ctx context.Context, userID, companionID string, product credits.Product, input map[string]any) (map[string]any, string, error) {
	switch product.Category {
	case "gift":
		note, _ := input["custom_request"].(string)
		return fulfillCatalogGift(ctx, userID, companionID, product, note)
	case "photo", "voice", "outfit":
		return nil, "", fmt.Errorf("media experiences require transactional delivery")
	case "keepsake":
		return fulfillKeepsake(ctx, userID, companionID, product)
	case "call":
		return nil, "", fmt.Errorf("real-time calling is not configured")
	default:
		return nil, "", fmt.Errorf("unsupported experience")
	}
}

func fulfillCatalogGift(ctx context.Context, userID, companionID string, product credits.Product, preferences ...string) (map[string]any, string, error) {
	intimacy := metadataInt(product.Metadata, "intimacy", 1)
	enthusiasm := metadataInt(product.Metadata, "enthusiasm", 2)
	id := uuid.New().String()
	conversationID, err := experienceConversation(ctx, userID, companionID)
	if err != nil {
		return nil, "", err
	}
	reaction := ""
	if companionAgent != nil {
		note := ""
		if len(preferences) > 0 {
			note = strings.TrimSpace(preferences[0])
		}
		reaction = companionAgent.ComposeInteractionReaction(ctx, userID, companionID, "gift", product.NameKey, note)
	}
	messageID := uuid.New().String()
	reactionID := uuid.New().String()
	memoryID := uuid.New().String()
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
	if reaction != "" {
		reactionPayload, _ := json.Marshal(map[string]any{"gift_id": id, "product_key": product.Key, "gesture": "receive_gift"})
		if _, err := tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,delivery_status,created_at)
			VALUES($1,$2,'assistant','text',$3,$4,'gift_reaction','delivered',$5)`, reactionID, conversationID, reaction, reactionPayload, createdAt.Add(time.Millisecond)); err != nil {
			return nil, "", err
		}
		memoryMetadata, _ := json.Marshal(map[string]any{"gift_id": id, "product_key": product.Key, "source": "gift_reaction"})
		if _, err := tx.ExecContext(ctx, `INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata)
			VALUES($1,$2,'gift_received',$3,60,$4,$5)`, memoryID, companionID, reaction, createdAt, string(memoryMetadata)); err != nil {
			return nil, "", err
		}
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
	var reactionMessage any
	if reaction != "" {
		reactionMessage = map[string]any{
			"id": reactionID, "conversation_id": conversationID,
			"sender_type": "assistant", "message_type": "text",
			"content": reaction, "media_url": "",
			"payload": map[string]any{"gift_id": id, "product_key": product.Key, "gesture": "receive_gift"},
			"source":  "gift_reaction", "life_event_id": "",
			"delivery_status": "delivered", "created_at": createdAt.Add(time.Millisecond),
		}
	}
	return map[string]any{
		"gift_id": id, "message_id": messageID, "emoji": product.Emoji,
		"reaction": reaction, "reaction_message_id": reactionID, "gesture": "receive_gift",
		"intimacy_delta": intimacy, "enthusiasm_delta": enthusiasm,
		"message": message, "reaction_message": reactionMessage, "memory_id": func() string {
			if reaction != "" {
				return memoryID
			}
			return ""
		}(),
	}, id, nil
}

func fulfillVirtualDate(ctx context.Context, userID, companionID string, product credits.Product, start time.Time, reaction string) (map[string]any, string, error) {
	duration := time.Duration(metadataInt(product.Metadata, "duration_minutes", 60)) * time.Minute
	location, _ := product.Metadata["location"].(string)
	eventID := uuid.New().String()
	memoryID := uuid.New().String()
	payload, _ := json.Marshal(map[string]any{"paid_experience": true, "product_key": product.Key, "with_user": true, "event_id": eventID, "memory_id": memoryID})
	title := product.NameKey
	description := product.DescriptionKey
	conversationID, err := experienceConversation(ctx, userID, companionID)
	if err != nil {
		return nil, "", err
	}
	if strings.TrimSpace(reaction) == "" {
		return nil, "", fmt.Errorf("companion could not respond to invitation")
	}
	messageID := uuid.New().String()
	reactionID := uuid.New().String()
	messageTime := time.Now().UTC()
	messagePayload, _ := json.Marshal(map[string]any{"event_id": eventID, "product_key": product.Key,
		"scheduled_at": start})
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
	if _, err := tx.ExecContext(ctx, `INSERT INTO life_events(id,companion_id,event_type,title,description,location,start_time,end_time,emotion,importance,user_relevance,shareability,status,local_date,sequence,payload,generation_source)
		VALUES($1,$2,'shared_activity',$3,$4,$5,$6,$7,'anticipating',85,100,false,'scheduled',$8::date,
			(SELECT COALESCE(MAX(sequence),-1)+1 FROM life_events WHERE companion_id=$2 AND local_date=$8::date),$9,'user_purchase')`,
		eventID, companionID, title, description, location, start, start.Add(duration), localDate, payload); err != nil {
		return nil, "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,life_event_id,delivery_status,created_at)
		VALUES($1,$2,'user','scene_card',$3,$4,'paid_date',$5,'delivered',$6)`, messageID, conversationID, description, messagePayload, eventID, messageTime); err != nil {
		return nil, "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,life_event_id,delivery_status,created_at)
		VALUES($1,$2,'assistant','text',$3,$4,'moment_invitation',$5,'delivered',$6)`, reactionID, conversationID, reaction, messagePayload, eventID, messageTime.Add(time.Millisecond)); err != nil {
		return nil, "", err
	}
	if err := tx.Commit(); err != nil {
		return nil, "", err
	}
	return map[string]any{"event_id": eventID, "memory_id": memoryID, "message_id": messageID, "reaction_message_id": reactionID, "scheduled_at": start}, eventID, nil
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

func experienceConversation(ctx context.Context, userID, companionID string) (string, error) {
	var id string
	err := db.Get().QueryRowContext(ctx, `SELECT id FROM conversations WHERE user_id=$1 AND companion_id=$2 AND id NOT LIKE 'date:%' ORDER BY created_at LIMIT 1`, userID, companionID).Scan(&id)
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
	blocks, err := loadExperienceBlocks(ctx, companionID, candidate, candidate.Add(31*24*time.Hour))
	if err != nil {
		return time.Time{}, err
	}
	for _, block := range blocks {
		if candidate.Add(duration).After(block.Start) && candidate.Before(block.End) {
			candidate = block.End.Add(15 * time.Minute)
		}
	}
	return candidate, nil
}

func requireExperienceCompanion(c *gin.Context, userID, companionID string) bool {
	var exists bool
	err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM companions WHERE id=$1 AND user_id=$2 AND active=true AND deleted_at IS NULL)`, companionID, userID).Scan(&exists)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to load companion"})
		return false
	}
	if !exists {
		c.JSON(404, gin.H{"error": "companion not found"})
		return false
	}
	return true
}

func requireExperienceAccess(c *gin.Context, userID, companionID string, productKeys ...string) bool {
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
	// An already purchased non-exclusive date remains usable without a subscription.
	if len(productKeys) > 0 && productKeys[0] != "" {
		var subscriptionOnly bool
		err := db.Get().QueryRow(`SELECT subscription_only FROM credit_products WHERE environment=$1 AND product_key=$2`, currentEnvironment(), productKeys[0]).Scan(&subscriptionOnly)
		if err != nil {
			c.JSON(500, gin.H{"error": "failed to load experience"})
			return false
		}
		if !subscriptionOnly {
			return true
		}
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
	case errors.Is(err, credits.ErrNotLaunched):
		c.JSON(http.StatusConflict, gin.H{"error": "experience is coming soon", "code": "experience_not_launched"})
	case errors.Is(err, credits.ErrSubscriptionRequired):
		subscriptionRequired(c, "experience_requires_subscription", "Subscribe to use this experience")
	case errors.Is(err, credits.ErrProductNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "experience is unavailable", "code": "product_unavailable"})
	case errors.Is(err, credits.ErrInsufficientCredit):
		c.JSON(http.StatusPaymentRequired, gin.H{"error": "insufficient credits", "code": "insufficient_credits", "action": "open_credits"})
	case errors.Is(err, credits.ErrPriceChanged):
		c.JSON(409, gin.H{"error": "experience price changed; confirm the new price", "code": "experience_price_changed"})
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
	environment := currentEnvironment()
	rows, err := db.Get().Query(`SELECT product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata::text,subscription_only,is_launched
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
		if err := rows.Scan(&item.Key, &item.Category, &item.NameKey, &item.DescriptionKey, &item.Emoji, &item.Coins, &item.Enabled, &item.SortOrder, &raw, &item.SubscriptionOnly, &item.IsLaunched); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan credit products"})
			return
		}
		_ = json.Unmarshal([]byte(raw), &item.Metadata)
		items = append(items, item)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminUpdateCreditProduct(c *gin.Context) {
	environment := currentEnvironment()
	var input struct {
		SceneAudioURL      *string `json:"scene_audio_url"`
		SceneBackgroundURL *string `json:"scene_background_url"`
		SubscriptionOnly   *bool   `json:"subscription_only"`
		IsLaunched         *bool   `json:"is_launched"`
		Coins              int     `json:"coins" binding:"required,min=1,max=100000"`
		Enabled            bool    `json:"enabled"`
		SortOrder          int     `json:"sort_order"`
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
	if category == "call" && input.Enabled && (input.IsLaunched == nil || *input.IsLaunched) {
		c.JSON(http.StatusConflict, gin.H{"error": "configure a real-time calling provider before enabling call products"})
		return
	}
	var scenePatch any
	patch := map[string]string{}
	for key, value := range map[string]*string{"scene_background_url": input.SceneBackgroundURL, "scene_audio_url": input.SceneAudioURL} {
		if value == nil {
			continue
		}
		asset := strings.TrimSpace(*value)
		parsed, parseErr := url.Parse(asset)
		if category != "date" || len(asset) > 2048 || (asset != "" && (parseErr != nil || !((parsed.Scheme == "https" && parsed.Host != "" && parsed.User == nil) || (key == "scene_background_url" && strings.HasPrefix(asset, "/v1/media/") && parsed.Host == "" && parsed.Scheme == "")))) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid scene asset URL"})
			return
		}
		patch[key] = asset
	}
	if len(patch) > 0 {
		encoded, _ := json.Marshal(patch)
		scenePatch = string(encoded)
	}
	result, err := db.Get().Exec(`UPDATE credit_products SET coins=$3,enabled=$4,sort_order=$5,subscription_only=COALESCE($6,subscription_only),is_launched=COALESCE($7,is_launched),metadata=COALESCE(metadata,'{}'::jsonb)||COALESCE($8::jsonb,'{}'::jsonb),updated_at=CURRENT_TIMESTAMP
		WHERE environment=$1 AND product_key=$2`, environment, c.Param("product_key"), input.Coins, input.Enabled, input.SortOrder, input.SubscriptionOnly, input.IsLaunched, scenePatch)
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

// Shared experiences follow the current App language, just like normal chat.
func syncExperienceLocale(c *gin.Context) bool {
	raw := strings.TrimSpace(c.GetHeader("Accept-Language"))
	if raw == "" {
		return true
	}
	if _, err := db.Get().ExecContext(c.Request.Context(), `UPDATE users SET preferred_locale=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND preferred_locale IS DISTINCT FROM $1`, language.Normalize(raw), c.GetString("user_id")); err != nil {
		c.JSON(500, gin.H{"error": "failed to save experience language"})
		return false
	}
	return true
}

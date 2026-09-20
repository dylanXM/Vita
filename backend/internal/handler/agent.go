package handler

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/agent"
	"vita/internal/db"
)

var companionAgent *agent.Service

func InitAgent(service *agent.Service) {
	companionAgent = service
}

type adminProvider struct {
	ID               string    `json:"id"`
	Name             string    `json:"name"`
	Kind             string    `json:"kind"`
	BaseURL          string    `json:"base_url"`
	APIKeyConfigured bool      `json:"api_key_configured"`
	Enabled          bool      `json:"enabled"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type adminModel struct {
	ID           string          `json:"id"`
	ProviderID   string          `json:"provider_id"`
	ProviderName string          `json:"provider_name"`
	ModelName    string          `json:"model_name"`
	DisplayName  string          `json:"display_name"`
	Capabilities json.RawMessage `json:"capabilities"`
	Enabled      bool            `json:"enabled"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
}

type agentSettingsResponse struct {
	ChatModelID         *string `json:"chat_model_id"`
	LifeModelID         *string `json:"life_model_id"`
	ProactiveModelID    *string `json:"proactive_model_id"`
	DailyEventMin       int     `json:"daily_event_min"`
	DailyEventMax       int     `json:"daily_event_max"`
	DailyProactiveLimit int     `json:"daily_proactive_limit"`
	QuietHoursStart     int     `json:"quiet_hours_start"`
	QuietHoursEnd       int     `json:"quiet_hours_end"`
}

type portraitResponse struct {
	ID              string          `json:"id"`
	Name            string          `json:"name"`
	ImageURL        string          `json:"image_url"`
	Gender          string          `json:"gender"`
	PersonalityTags json.RawMessage `json:"personality_tags"`
	Enabled         bool            `json:"enabled"`
	SortOrder       int             `json:"sort_order"`
}

func AdminAgentConfig(c *gin.Context) {
	providers, err := loadAdminProviders()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load providers"})
		return
	}
	models, err := loadAdminModels()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load models"})
		return
	}
	settings, err := loadAgentSettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load agent settings"})
		return
	}
	portraits, err := loadPortraits(false)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load portraits"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"providers": providers, "models": models, "settings": settings, "portraits": portraits,
	})
}

type providerInput struct {
	Name    string `json:"name" binding:"required"`
	Kind    string `json:"kind" binding:"required"`
	BaseURL string `json:"base_url"`
	APIKey  string `json:"api_key"`
	Enabled *bool  `json:"enabled"`
}

func AdminCreateProvider(c *gin.Context) { upsertProvider(c, "") }
func AdminUpdateProvider(c *gin.Context) { upsertProvider(c, c.Param("id")) }

func upsertProvider(c *gin.Context, id string) {
	if companionAgent == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "agent service is unavailable"})
		return
	}
	var input providerInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Kind = strings.ToLower(strings.TrimSpace(input.Kind))
	if input.Kind != "openai" && input.Kind != "anthropic" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "kind must be openai or anthropic"})
		return
	}
	if id == "" {
		id = uuid.New().String()
	}
	enabled := true
	if input.Enabled != nil {
		enabled = *input.Enabled
	}
	encrypted := ""
	var err error
	if input.APIKey != "" {
		encrypted, err = companionAgent.EncryptSecret(input.APIKey)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to protect provider key"})
			return
		}
	}
	if c.Request.Method == http.MethodPost {
		_, err = db.Get().Exec(`INSERT INTO ai_providers (id,name,kind,base_url,api_key_ciphertext,enabled) VALUES ($1,$2,$3,$4,$5,$6)`,
			id, strings.TrimSpace(input.Name), input.Kind, strings.TrimSpace(input.BaseURL), encrypted, enabled)
	} else {
		if input.APIKey == "" {
			_, err = db.Get().Exec(`UPDATE ai_providers SET name=$2,kind=$3,base_url=$4,enabled=$5,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
				id, strings.TrimSpace(input.Name), input.Kind, strings.TrimSpace(input.BaseURL), enabled)
		} else {
			_, err = db.Get().Exec(`UPDATE ai_providers SET name=$2,kind=$3,base_url=$4,api_key_ciphertext=$5,enabled=$6,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
				id, strings.TrimSpace(input.Name), input.Kind, strings.TrimSpace(input.BaseURL), encrypted, enabled)
		}
	}
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save provider"})
		return
	}
	providers, _ := loadAdminProviders()
	for _, provider := range providers {
		if provider.ID == id {
			c.JSON(http.StatusOK, provider)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "provider not found"})
}

func AdminDeleteProvider(c *gin.Context) {
	result, err := db.Get().Exec(`DELETE FROM ai_providers WHERE id = $1`, c.Param("id"))
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "provider is still in use"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "provider not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "provider deleted"})
}

type modelInput struct {
	ProviderID   string   `json:"provider_id" binding:"required"`
	ModelName    string   `json:"model_name" binding:"required"`
	DisplayName  string   `json:"display_name" binding:"required"`
	Capabilities []string `json:"capabilities"`
	Enabled      *bool    `json:"enabled"`
}

func AdminCreateModel(c *gin.Context) { upsertModel(c, "") }
func AdminUpdateModel(c *gin.Context) { upsertModel(c, c.Param("id")) }

func upsertModel(c *gin.Context, id string) {
	var input modelInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if id == "" {
		id = uuid.New().String()
	}
	if len(input.Capabilities) == 0 {
		input.Capabilities = []string{"text"}
	}
	for _, capability := range input.Capabilities {
		if capability != "text" && capability != "image" && capability != "audio" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported model capability"})
			return
		}
	}
	capabilities, _ := json.Marshal(input.Capabilities)
	enabled := true
	if input.Enabled != nil {
		enabled = *input.Enabled
	}
	var err error
	if c.Request.Method == http.MethodPost {
		_, err = db.Get().Exec(`INSERT INTO ai_models (id,provider_id,model_name,display_name,capabilities,enabled) VALUES ($1,$2,$3,$4,$5,$6)`,
			id, input.ProviderID, strings.TrimSpace(input.ModelName), strings.TrimSpace(input.DisplayName), capabilities, enabled)
	} else {
		_, err = db.Get().Exec(`UPDATE ai_models SET provider_id=$2,model_name=$3,display_name=$4,capabilities=$5,enabled=$6,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
			id, input.ProviderID, strings.TrimSpace(input.ModelName), strings.TrimSpace(input.DisplayName), capabilities, enabled)
	}
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save model"})
		return
	}
	models, _ := loadAdminModels()
	for _, model := range models {
		if model.ID == id {
			c.JSON(http.StatusOK, model)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "model not found"})
}

func AdminDeleteModel(c *gin.Context) {
	result, err := db.Get().Exec(`DELETE FROM ai_models WHERE id = $1`, c.Param("id"))
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "model is still in use"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "model not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "model deleted"})
}

func AdminUpdateAgentSettings(c *gin.Context) {
	var input agentSettingsResponse
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if input.DailyEventMin < 1 || input.DailyEventMax < input.DailyEventMin || input.DailyEventMax > 24 ||
		input.DailyProactiveLimit < 0 || input.DailyProactiveLimit > 8 ||
		input.QuietHoursStart < 0 || input.QuietHoursStart > 23 || input.QuietHoursEnd < 0 || input.QuietHoursEnd > 23 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid agent limits"})
		return
	}
	_, err := db.Get().Exec(`
		UPDATE agent_settings SET chat_model_id=$1,life_model_id=$2,proactive_model_id=$3,
		daily_event_min=$4,daily_event_max=$5,daily_proactive_limit=$6,quiet_hours_start=$7,quiet_hours_end=$8,
		updated_at=CURRENT_TIMESTAMP WHERE id='default'`, input.ChatModelID, input.LifeModelID, input.ProactiveModelID,
		input.DailyEventMin, input.DailyEventMax, input.DailyProactiveLimit, input.QuietHoursStart, input.QuietHoursEnd)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save agent settings"})
		return
	}
	settings, _ := loadAgentSettings()
	c.JSON(http.StatusOK, settings)
}

type portraitInput struct {
	Name            string   `json:"name" binding:"required"`
	ImageURL        string   `json:"image_url" binding:"required"`
	Gender          string   `json:"gender"`
	PersonalityTags []string `json:"personality_tags"`
	Enabled         *bool    `json:"enabled"`
	SortOrder       int      `json:"sort_order"`
}

func AdminCreatePortrait(c *gin.Context) { upsertPortrait(c, "") }
func AdminUpdatePortrait(c *gin.Context) { upsertPortrait(c, c.Param("id")) }

func upsertPortrait(c *gin.Context, id string) {
	var input portraitInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if id == "" {
		id = uuid.New().String()
	}
	tags, _ := json.Marshal(input.PersonalityTags)
	enabled := true
	if input.Enabled != nil {
		enabled = *input.Enabled
	}
	var err error
	if c.Request.Method == http.MethodPost {
		_, err = db.Get().Exec(`INSERT INTO companion_portraits (id,name,image_url,gender,personality_tags,enabled,sort_order) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
			id, input.Name, input.ImageURL, input.Gender, tags, enabled, input.SortOrder)
	} else {
		_, err = db.Get().Exec(`UPDATE companion_portraits SET name=$2,image_url=$3,gender=$4,personality_tags=$5,enabled=$6,sort_order=$7,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
			id, input.Name, input.ImageURL, input.Gender, tags, enabled, input.SortOrder)
	}
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save portrait"})
		return
	}
	portraits, _ := loadPortraits(false)
	for _, portrait := range portraits {
		if portrait.ID == id {
			c.JSON(http.StatusOK, portrait)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "portrait not found"})
}

func CompanionOptions(c *gin.Context) {
	portraits, err := loadPortraits(true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion options"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"personality_tags": []string{"warm", "independent", "witty", "gentle", "curious", "calm", "outgoing", "thoughtful", "ambitious", "playful"},
		"portraits":        portraits,
		"creation_sources": []string{"tags_portrait", "chat_history", "user_images", "admin"},
	})
}

// AgentNotifications consumes in-app notification outbox entries. External
// push channels can be added beside in_app without changing the message model.
func AgentNotifications(c *gin.Context) {
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load notifications"})
		return
	}
	defer tx.Rollback()

	rows, err := tx.QueryContext(c.Request.Context(), `
		SELECT o.id, o.companion_id, o.message_id, o.payload::text, o.created_at
		FROM notification_outbox o
		WHERE o.user_id=$1 AND o.channel='in_app' AND o.status='ready'
		  AND o.available_at <= CURRENT_TIMESTAMP
		ORDER BY o.created_at ASC LIMIT 3 FOR UPDATE SKIP LOCKED`, c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load notifications"})
		return
	}
	type notification struct {
		ID          string          `json:"id"`
		CompanionID string          `json:"companion_id"`
		MessageID   sql.NullString  `json:"-"`
		Payload     json.RawMessage `json:"payload"`
		CreatedAt   time.Time       `json:"created_at"`
	}
	items := make([]notification, 0)
	for rows.Next() {
		var item notification
		var raw string
		if err := rows.Scan(&item.ID, &item.CompanionID, &item.MessageID, &raw, &item.CreatedAt); err != nil {
			rows.Close()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read notifications"})
			return
		}
		item.Payload = json.RawMessage(raw)
		items = append(items, item)
	}
	if err := rows.Close(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read notifications"})
		return
	}
	for _, item := range items {
		if _, err := tx.ExecContext(c.Request.Context(), `
			UPDATE notification_outbox SET status='sent',sent_at=CURRENT_TIMESTAMP,attempts=attempts+1
			WHERE id=$1`, item.ID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to acknowledge notifications"})
			return
		}
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to acknowledge notifications"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

type adminCompanionInput struct {
	UserID            string   `json:"user_id"`
	Name              string   `json:"name" binding:"required"`
	Gender            string   `json:"gender"`
	Persona           string   `json:"persona"`
	City              string   `json:"city"`
	Occupation        string   `json:"occupation"`
	Interests         string   `json:"interests"`
	RelationshipStage string   `json:"relationship_stage"`
	PersonalityTags   []string `json:"personality_tags"`
	SpeakingStyle     string   `json:"speaking_style"`
	Likes             string   `json:"likes"`
	Dislikes          string   `json:"dislikes"`
	LifeHabits        string   `json:"life_habits"`
	LifeGoal          string   `json:"life_goal"`
	Backstory         string   `json:"backstory"`
	PortraitID        *string  `json:"portrait_id"`
	ModelID           *string  `json:"model_id"`
	ProactiveEnabled  *bool    `json:"proactive_enabled"`
	Active            *bool    `json:"active"`
}

func AdminListCompanions(c *gin.Context) {
	rows, err := db.Get().Query(`
		SELECT c.id,c.user_id,u.email,c.name,COALESCE(c.gender,''),COALESCE(c.persona,''),COALESCE(c.city,''),COALESCE(c.occupation,''),
		COALESCE(c.interests,''),COALESCE(c.relationship_stage,'stranger'),c.personality_tags::text,c.speaking_style,c.likes,c.dislikes,
		c.life_habits,c.life_goal,c.backstory,c.model_id,c.portrait_id,c.proactive_enabled,c.active,c.created_at,c.updated_at
		FROM companions c JOIN users u ON u.id=c.user_id ORDER BY c.created_at DESC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list companions"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, userID, email, name, gender, persona, city, occupation, interests, relationshipStage string
		var speakingStyle, likes, dislikes, lifeHabits, lifeGoal, backstory string
		var tags json.RawMessage
		var modelID, portraitID sql.NullString
		var proactive, active bool
		var created, updated time.Time
		if err := rows.Scan(&id, &userID, &email, &name, &gender, &persona, &city, &occupation, &interests, &relationshipStage, &tags, &speakingStyle, &likes, &dislikes, &lifeHabits, &lifeGoal, &backstory, &modelID, &portraitID, &proactive, &active, &created, &updated); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read companions"})
			return
		}
		items = append(items, gin.H{"id": id, "user_id": userID, "user_email": email, "name": name, "gender": gender, "persona": persona, "city": city, "occupation": occupation, "interests": interests, "relationship_stage": relationshipStage, "personality_tags": tags, "speaking_style": speakingStyle, "likes": likes, "dislikes": dislikes, "life_habits": lifeHabits, "life_goal": lifeGoal, "backstory": backstory, "model_id": nullString(modelID), "portrait_id": nullString(portraitID), "proactive_enabled": proactive, "active": active, "created_at": created, "updated_at": updated})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminCreateCompanion(c *gin.Context) { saveAdminCompanion(c, "") }
func AdminUpdateCompanion(c *gin.Context) { saveAdminCompanion(c, c.Param("id")) }

func saveAdminCompanion(c *gin.Context, id string) {
	var input adminCompanionInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if id == "" && input.UserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id is required"})
		return
	}
	tags, _ := json.Marshal(input.PersonalityTags)
	proactive, active := true, true
	if input.ProactiveEnabled != nil {
		proactive = *input.ProactiveEnabled
	}
	if input.Active != nil {
		active = *input.Active
	}
	if input.RelationshipStage == "" {
		input.RelationshipStage = "stranger"
	}
	if id == "" {
		id = uuid.New().String()
		tx, err := db.Get().Begin()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create companion"})
			return
		}
		defer tx.Rollback()
		_, err = tx.Exec(`INSERT INTO companions (id,user_id,name,gender,persona,city,occupation,interests,relationship_stage,personality_tags,speaking_style,likes,dislikes,life_habits,life_goal,backstory,portrait_id,model_id,creation_source,proactive_enabled,active) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,'admin',$19,$20)`,
			id, input.UserID, input.Name, input.Gender, input.Persona, input.City, input.Occupation, input.Interests, input.RelationshipStage, tags, input.SpeakingStyle, input.Likes, input.Dislikes, input.LifeHabits, input.LifeGoal, input.Backstory, input.PortraitID, input.ModelID, proactive, active)
		if err == nil {
			_, err = tx.Exec(`INSERT INTO relationship_states (companion_id) VALUES ($1) ON CONFLICT DO NOTHING`, id)
		}
		if err == nil {
			_, err = tx.Exec(`INSERT INTO companion_states (companion_id) VALUES ($1) ON CONFLICT DO NOTHING`, id)
		}
		if err == nil {
			err = tx.Commit()
		}
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "failed to create companion"})
			return
		}
	} else {
		result, err := db.Get().Exec(`UPDATE companions SET name=$2,gender=$3,persona=$4,city=$5,occupation=$6,interests=$7,relationship_stage=$8,personality_tags=$9,speaking_style=$10,likes=$11,dislikes=$12,life_habits=$13,life_goal=$14,backstory=$15,portrait_id=$16,model_id=$17,proactive_enabled=$18,active=$19,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
			id, input.Name, input.Gender, input.Persona, input.City, input.Occupation, input.Interests, input.RelationshipStage, tags, input.SpeakingStyle, input.Likes, input.Dislikes, input.LifeHabits, input.LifeGoal, input.Backstory, input.PortraitID, input.ModelID, proactive, active)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "failed to update companion"})
			return
		}
		if count, _ := result.RowsAffected(); count == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{"id": id})
}

func loadAdminProviders() ([]adminProvider, error) {
	rows, err := db.Get().Query(`SELECT id,name,kind,base_url,(api_key_ciphertext <> ''),enabled,created_at,updated_at FROM ai_providers ORDER BY created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]adminProvider, 0)
	for rows.Next() {
		var item adminProvider
		if err := rows.Scan(&item.ID, &item.Name, &item.Kind, &item.BaseURL, &item.APIKeyConfigured, &item.Enabled, &item.CreatedAt, &item.UpdatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func loadAdminModels() ([]adminModel, error) {
	rows, err := db.Get().Query(`SELECT m.id,m.provider_id,p.name,m.model_name,m.display_name,m.capabilities::text,m.enabled,m.created_at,m.updated_at FROM ai_models m JOIN ai_providers p ON p.id=m.provider_id ORDER BY m.created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]adminModel, 0)
	for rows.Next() {
		var item adminModel
		var raw string
		if err := rows.Scan(&item.ID, &item.ProviderID, &item.ProviderName, &item.ModelName, &item.DisplayName, &raw, &item.Enabled, &item.CreatedAt, &item.UpdatedAt); err != nil {
			return nil, err
		}
		item.Capabilities = json.RawMessage(raw)
		items = append(items, item)
	}
	return items, rows.Err()
}

func loadAgentSettings() (agentSettingsResponse, error) {
	var output agentSettingsResponse
	var chat, life, proactive sql.NullString
	err := db.Get().QueryRow(`SELECT chat_model_id,life_model_id,proactive_model_id,daily_event_min,daily_event_max,daily_proactive_limit,quiet_hours_start,quiet_hours_end FROM agent_settings WHERE id='default'`).Scan(&chat, &life, &proactive, &output.DailyEventMin, &output.DailyEventMax, &output.DailyProactiveLimit, &output.QuietHoursStart, &output.QuietHoursEnd)
	output.ChatModelID = nullString(chat)
	output.LifeModelID = nullString(life)
	output.ProactiveModelID = nullString(proactive)
	return output, err
}

func loadPortraits(enabledOnly bool) ([]portraitResponse, error) {
	query := `SELECT id,name,image_url,gender,personality_tags::text,enabled,sort_order FROM companion_portraits`
	if enabledOnly {
		query += ` WHERE enabled=true`
	}
	query += ` ORDER BY sort_order,name`
	rows, err := db.Get().Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]portraitResponse, 0)
	for rows.Next() {
		var item portraitResponse
		var raw string
		if err := rows.Scan(&item.ID, &item.Name, &item.ImageURL, &item.Gender, &raw, &item.Enabled, &item.SortOrder); err != nil {
			return nil, err
		}
		item.PersonalityTags = json.RawMessage(raw)
		items = append(items, item)
	}
	return items, rows.Err()
}

func nullString(value sql.NullString) *string {
	if !value.Valid {
		return nil
	}
	return &value.String
}

func nullTime(value sql.NullTime) *time.Time {
	if !value.Valid {
		return nil
	}
	return &value.Time
}

func isNoRows(err error) bool { return errors.Is(err, sql.ErrNoRows) }

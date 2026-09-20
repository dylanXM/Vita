package handler

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/agent"
	"vita/internal/db"
	"vita/internal/language"
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
	ID                  string          `json:"id"`
	ProviderID          string          `json:"provider_id"`
	ProviderName        string          `json:"provider_name"`
	ModelName           string          `json:"model_name"`
	DisplayName         string          `json:"display_name"`
	Capabilities        json.RawMessage `json:"capabilities"`
	ConfiguredScenarios json.RawMessage `json:"configured_scenarios"`
	Enabled             bool            `json:"enabled"`
	CreatedAt           time.Time       `json:"created_at"`
	UpdatedAt           time.Time       `json:"updated_at"`
}

type modelTestResult struct {
	Scenario string `json:"scenario"`
	Success  bool   `json:"success"`
	Error    string `json:"error,omitempty"`
}

type agentSettingsResponse struct {
	ChatModelID          *string `json:"chat_model_id"`
	LifeModelID          *string `json:"life_model_id"`
	ProactiveModelID     *string `json:"proactive_model_id"`
	ImageModelID         *string `json:"image_model_id"`
	TranscriptionModelID *string `json:"transcription_model_id"`
	SpeechModelID        *string `json:"speech_model_id"`
	DailyEventMin        int     `json:"daily_event_min"`
	DailyEventMax        int     `json:"daily_event_max"`
	DailyProactiveLimit  int     `json:"daily_proactive_limit"`
	DailyLifePhotoLimit  int     `json:"daily_life_photo_limit"`
	QuietHoursStart      int     `json:"quiet_hours_start"`
	QuietHoursEnd        int     `json:"quiet_hours_end"`
	FreeDefaultChatHours int     `json:"free_default_chat_hours"`
}

type portraitResponse struct {
	ID              string          `json:"id"`
	Name            string          `json:"name"`
	ImageURL        string          `json:"image_url"`
	Gender          string          `json:"gender"`
	PersonalityTags json.RawMessage `json:"personality_tags"`
	IsDefault       bool            `json:"is_default"`
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
	var usedByMediaRoute bool
	if err := db.Get().QueryRow(`SELECT EXISTS(
		SELECT 1 FROM ai_models m
		JOIN agent_media_routes r ON r.primary_model_id=m.id OR r.fallback_model_ids ? m.id
		WHERE m.provider_id=$1
	)`, c.Param("id")).Scan(&usedByMediaRoute); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check provider usage"})
		return
	}
	if usedByMediaRoute {
		c.JSON(http.StatusConflict, gin.H{"error": "provider has models used by a model route"})
		return
	}
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

type modelCreateInput struct {
	ProviderID   string   `json:"provider_id" binding:"required"`
	ModelName    string   `json:"model_name" binding:"required"`
	DisplayName  string   `json:"display_name" binding:"required"`
	Scenarios    []string `json:"scenarios"`
	Capabilities []string `json:"capabilities"`
	Enabled      *bool    `json:"enabled"`
}

const (
	maxModelTestUploadBytes  = 12 << 20
	maxModelTestRequestBytes = 13 << 20
)

var modelScenarioCapabilities = map[string]string{
	"text_chat":             "text",
	"text_life_plan":        "text",
	"text_proactive":        "text",
	"image_life_photo":      "image",
	"image_requested_photo": "image",
	"audio_transcription":   "audio",
	"audio_speech":          "audio",
	"video_life_clip":       "video",
	"video_realtime_avatar": "video",
}

var orderedModelScenarios = []string{
	"text_chat", "text_life_plan", "text_proactive",
	"image_life_photo", "image_requested_photo",
	"audio_transcription", "audio_speech",
	"video_life_clip", "video_realtime_avatar",
}

func AdminCreateModel(c *gin.Context) {
	var input modelCreateInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.ProviderID = strings.TrimSpace(input.ProviderID)
	input.ModelName = strings.TrimSpace(input.ModelName)
	input.DisplayName = strings.TrimSpace(input.DisplayName)
	if input.ProviderID == "" || input.ModelName == "" || input.DisplayName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "provider, model ID, and display name are required"})
		return
	}
	if len(input.Scenarios) == 0 {
		legacyScenarios, legacyErr := scenariosForCapabilities(input.Capabilities)
		if legacyErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": legacyErr.Error()})
			return
		}
		input.Scenarios = legacyScenarios
	}
	scenarios, capabilities, err := normalizeModelScenarios(input.Scenarios)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var alreadyExists bool
	if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM ai_models WHERE provider_id=$1 AND model_name=$2)`, input.ProviderID, input.ModelName).Scan(&alreadyExists); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check model"})
		return
	}
	if alreadyExists {
		c.JSON(http.StatusConflict, gin.H{"error": "this provider and model ID already exist"})
		return
	}
	enabled := true
	if input.Enabled != nil {
		enabled = *input.Enabled
	}
	capabilitiesJSON, _ := json.Marshal(capabilities)
	id := uuid.New().String()
	configuredScenariosJSON, _ := json.Marshal(scenarios)
	if _, err := db.Get().Exec(`INSERT INTO ai_models (id,provider_id,model_name,display_name,capabilities,configured_scenarios,enabled) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
		id, input.ProviderID, input.ModelName, input.DisplayName, capabilitiesJSON, configuredScenariosJSON, enabled); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save model"})
		return
	}
	respondWithAdminModel(c, id)
}

func scenariosForCapabilities(capabilities []string) ([]string, error) {
	if len(capabilities) == 0 {
		return nil, errors.New("select at least one model scenario")
	}
	wanted := make(map[string]bool, len(capabilities))
	for _, raw := range capabilities {
		capability := strings.TrimSpace(raw)
		if capability != "text" && capability != "image" && capability != "audio" && capability != "video" {
			return nil, fmt.Errorf("unsupported model capability %q", capability)
		}
		wanted[capability] = true
	}
	scenarios := make([]string, 0)
	for _, scenario := range orderedModelScenarios {
		if wanted[modelScenarioCapabilities[scenario]] {
			scenarios = append(scenarios, scenario)
		}
	}
	return scenarios, nil
}

func AdminTestModel(c *gin.Context) {
	if companionAgent == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "agent service is unavailable"})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxModelTestRequestBytes)
	if err := c.Request.ParseMultipartForm(maxModelTestRequestBytes); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid model test form or upload is too large"})
		return
	}
	defer c.Request.MultipartForm.RemoveAll()
	providerID := strings.TrimSpace(c.PostForm("provider_id"))
	modelName := strings.TrimSpace(c.PostForm("model_name"))
	if providerID == "" || modelName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "provider and model ID are required"})
		return
	}
	var requestedScenarios []string
	if err := json.Unmarshal([]byte(c.PostForm("scenarios")), &requestedScenarios); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "scenarios must be a JSON array"})
		return
	}
	scenarios, _, err := normalizeModelScenarios(requestedScenarios)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	model, loadErr := loadModelForValidation(providerID, modelName)
	var testAudio *agent.ModelTestAudio
	var audioErr error
	if slices.Contains(scenarios, "audio_transcription") {
		testAudio, audioErr = readModelTestAudio(c)
	}
	client := agent.NewClient()
	results := collectModelTestResults(scenarios, func(scenario string) error {
		testErr := loadErr
		if testErr == nil && scenario == "audio_transcription" && audioErr != nil {
			testErr = audioErr
		}
		if testErr == nil {
			testErr = agent.TestModelScenario(c.Request.Context(), client, model, scenario, testAudio)
		}
		return testErr
	})
	c.JSON(http.StatusOK, gin.H{"results": results})
}

func collectModelTestResults(scenarios []string, test func(string) error) []modelTestResult {
	results := make([]modelTestResult, 0, len(scenarios))
	for _, scenario := range scenarios {
		err := test(scenario)
		result := modelTestResult{Scenario: scenario, Success: err == nil}
		if err != nil {
			result.Error = err.Error()
		}
		results = append(results, result)
	}
	return results
}

func AdminUpdateModel(c *gin.Context) { updateModel(c, c.Param("id")) }

func updateModel(c *gin.Context, id string) {
	var input modelInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	enabled := true
	if input.Enabled != nil {
		enabled = *input.Enabled
	}
	var storedProviderID, storedModelName, storedCapabilities string
	if err := db.Get().QueryRow(`SELECT provider_id,model_name,capabilities FROM ai_models WHERE id=$1`, id).Scan(&storedProviderID, &storedModelName, &storedCapabilities); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "model not found"})
		return
	}
	requestedCapabilities, _ := json.Marshal(input.Capabilities)
	if input.ProviderID != storedProviderID || strings.TrimSpace(input.ModelName) != storedModelName || !jsonEqual([]byte(storedCapabilities), requestedCapabilities) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "provider, model ID, and capabilities cannot be changed; add a new model instead"})
		return
	}
	_, err := db.Get().Exec(`UPDATE ai_models SET display_name=$2,enabled=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
		id, strings.TrimSpace(input.DisplayName), enabled)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save model"})
		return
	}
	respondWithAdminModel(c, id)
}

func normalizeModelScenarios(input []string) ([]string, []string, error) {
	if len(input) == 0 {
		return nil, nil, errors.New("select at least one testable model scenario")
	}
	seenScenarios := make(map[string]bool, len(input))
	seenCapabilities := make(map[string]bool)
	scenarios := make([]string, 0, len(input))
	for _, raw := range input {
		scenario := strings.TrimSpace(raw)
		capability, ok := modelScenarioCapabilities[scenario]
		if !ok {
			return nil, nil, fmt.Errorf("scenario %q has no runtime validation adapter", scenario)
		}
		if seenScenarios[scenario] {
			return nil, nil, fmt.Errorf("scenario %q is duplicated", scenario)
		}
		seenScenarios[scenario] = true
		seenCapabilities[capability] = true
		scenarios = append(scenarios, scenario)
	}
	capabilities := make([]string, 0, len(seenCapabilities))
	for _, capability := range []string{"text", "image", "audio", "video"} {
		if seenCapabilities[capability] {
			capabilities = append(capabilities, capability)
		}
	}
	return scenarios, capabilities, nil
}

func loadModelForValidation(providerID, modelName string) (agent.Model, error) {
	var model agent.Model
	var encryptedKey string
	if err := db.Get().QueryRow(`SELECT id,kind,base_url,api_key_ciphertext FROM ai_providers WHERE id=$1 AND enabled=true AND api_key_ciphertext <> ''`, providerID).
		Scan(&model.ID, &model.Kind, &model.BaseURL, &encryptedKey); err != nil {
		return model, err
	}
	apiKey, err := companionAgent.DecryptSecret(encryptedKey)
	if err != nil {
		return model, err
	}
	model.APIKey = apiKey
	model.ModelName = modelName
	return model, nil
}

func readModelTestAudio(c *gin.Context) (*agent.ModelTestAudio, error) {
	header, err := c.FormFile("transcription_file")
	if err != nil {
		return nil, errors.New("a test audio file is required for audio transcription")
	}
	file, err := header.Open()
	if err != nil {
		return nil, errors.New("failed to open the test audio file")
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxModelTestUploadBytes+1))
	if err != nil || len(data) == 0 || len(data) > maxModelTestUploadBytes {
		return nil, errors.New("test audio must be a non-empty file no larger than 12 MB")
	}
	mimeType := header.Header.Get("Content-Type")
	if mimeType == "" {
		mimeType = http.DetectContentType(data)
	}
	return &agent.ModelTestAudio{Filename: header.Filename, MIMEType: mimeType, Data: data}, nil
}

func respondWithAdminModel(c *gin.Context, id string) {
	models, _ := loadAdminModels()
	for _, model := range models {
		if model.ID == id {
			c.JSON(http.StatusOK, model)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "model not found"})
}

func jsonEqual(left, right []byte) bool {
	var a, b []string
	return json.Unmarshal(left, &a) == nil && json.Unmarshal(right, &b) == nil && slices.Equal(a, b)
}

type mediaModelRoute struct {
	RouteKey         string   `json:"route_key"`
	MediaType        string   `json:"media_type"`
	Enabled          bool     `json:"enabled"`
	PrimaryModelID   *string  `json:"primary_model_id"`
	FallbackModelIDs []string `json:"fallback_model_ids"`
}

var mediaRouteTypes = map[string]string{
	"text_chat":             "text",
	"text_life_plan":        "text",
	"text_proactive":        "text",
	"image_life_photo":      "image",
	"image_requested_photo": "image",
	"audio_transcription":   "audio",
	"audio_speech":          "audio",
	"video_life_clip":       "video",
	"video_realtime_avatar": "video",
}

func AdminListMediaModelRoutes(c *gin.Context) {
	routes, err := loadMediaModelRoutes()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load model routes"})
		return
	}
	models, err := loadAdminModels()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load models"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"routes": routes, "models": models})
}

func AdminUpdateMediaModelRoutes(c *gin.Context) {
	var input struct {
		Routes []mediaModelRoute `json:"routes" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid model routes"})
		return
	}
	normalizedRoutes, err := normalizeMediaModelRoutes(input.Routes)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Routes = normalizedRoutes
	for _, route := range input.Routes {
		expectedType := mediaRouteTypes[route.RouteKey]
		modelIDs := append([]string{}, route.FallbackModelIDs...)
		if route.PrimaryModelID != nil {
			modelIDs = append([]string{*route.PrimaryModelID}, modelIDs...)
		}
		for _, modelID := range modelIDs {
			var valid bool
			if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM ai_models WHERE id=$1 AND enabled=true AND capabilities ? $2 AND configured_scenarios ? $3)`, modelID, expectedType, route.RouteKey).Scan(&valid); err != nil || !valid {
				c.JSON(http.StatusBadRequest, gin.H{"error": "a selected model is not configured for " + route.RouteKey})
				return
			}
		}
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save model routes"})
		return
	}
	defer tx.Rollback()
	for _, route := range input.Routes {
		fallbacks, _ := json.Marshal(route.FallbackModelIDs)
		if _, err := tx.ExecContext(c.Request.Context(), `UPDATE agent_media_routes SET enabled=$2,primary_model_id=$3,fallback_model_ids=$4,updated_at=CURRENT_TIMESTAMP WHERE route_key=$1`, route.RouteKey, route.Enabled, route.PrimaryModelID, fallbacks); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save model routes"})
			return
		}
	}
	if _, err := tx.ExecContext(c.Request.Context(), `UPDATE agent_settings SET
		chat_model_id=(SELECT CASE WHEN enabled THEN primary_model_id END FROM agent_media_routes WHERE route_key='text_chat'),
		life_model_id=(SELECT CASE WHEN enabled THEN primary_model_id END FROM agent_media_routes WHERE route_key='text_life_plan'),
		proactive_model_id=(SELECT CASE WHEN enabled THEN primary_model_id END FROM agent_media_routes WHERE route_key='text_proactive'),
		image_model_id=(SELECT CASE WHEN enabled THEN primary_model_id END FROM agent_media_routes WHERE route_key='image_life_photo'),
		transcription_model_id=(SELECT CASE WHEN enabled THEN primary_model_id END FROM agent_media_routes WHERE route_key='audio_transcription'),
		speech_model_id=(SELECT CASE WHEN enabled THEN primary_model_id END FROM agent_media_routes WHERE route_key='audio_speech'),updated_at=CURRENT_TIMESTAMP
		WHERE id='default'`); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to sync legacy media settings"})
		return
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save model routes"})
		return
	}
	AdminListMediaModelRoutes(c)
}

func normalizeMediaModelRoutes(routes []mediaModelRoute) ([]mediaModelRoute, error) {
	normalized := make([]mediaModelRoute, 0, len(routes))
	seen := map[string]bool{}
	for _, inputRoute := range routes {
		route := inputRoute
		if route.PrimaryModelID != nil {
			modelID := strings.TrimSpace(*route.PrimaryModelID)
			if modelID == "" {
				route.PrimaryModelID = nil
			} else {
				route.PrimaryModelID = &modelID
			}
		}
		fallbacks := make([]string, 0, len(route.FallbackModelIDs))
		for _, modelID := range route.FallbackModelIDs {
			if modelID = strings.TrimSpace(modelID); modelID != "" {
				fallbacks = append(fallbacks, modelID)
			}
		}
		route.FallbackModelIDs = fallbacks
		expectedType, ok := mediaRouteTypes[route.RouteKey]
		if !ok || route.MediaType != expectedType || seen[route.RouteKey] || len(route.FallbackModelIDs) > 5 {
			return nil, errors.New("invalid model route")
		}
		seen[route.RouteKey] = true
		if route.Enabled && route.PrimaryModelID == nil {
			return nil, errors.New("enabled routes require a default model")
		}
		modelIDs := append([]string{}, route.FallbackModelIDs...)
		if route.PrimaryModelID != nil {
			modelIDs = append([]string{*route.PrimaryModelID}, modelIDs...)
		}
		unique := map[string]bool{}
		for _, modelID := range modelIDs {
			if unique[modelID] {
				return nil, errors.New("model route models must be unique")
			}
			unique[modelID] = true
		}
		normalized = append(normalized, route)
	}
	if len(seen) != len(mediaRouteTypes) {
		return nil, errors.New("all model routes are required")
	}
	return normalized, nil
}

func loadMediaModelRoutes() ([]mediaModelRoute, error) {
	rows, err := db.Get().Query(`SELECT route_key,media_type,enabled,primary_model_id,fallback_model_ids::text
		FROM agent_media_routes ORDER BY media_type,route_key`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	routes := make([]mediaModelRoute, 0, len(mediaRouteTypes))
	for rows.Next() {
		var route mediaModelRoute
		var primary sql.NullString
		var fallbacks string
		if err := rows.Scan(&route.RouteKey, &route.MediaType, &route.Enabled, &primary, &fallbacks); err != nil {
			return nil, err
		}
		route.PrimaryModelID = nullString(primary)
		_ = json.Unmarshal([]byte(fallbacks), &route.FallbackModelIDs)
		routes = append(routes, route)
	}
	return routes, rows.Err()
}

func AdminDeleteModel(c *gin.Context) {
	var usedByMediaRoute bool
	if err := db.Get().QueryRow(`SELECT EXISTS(
		SELECT 1 FROM agent_media_routes
		WHERE primary_model_id=$1 OR fallback_model_ids ? $1
	)`, c.Param("id")).Scan(&usedByMediaRoute); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check model usage"})
		return
	}
	if usedByMediaRoute {
		c.JSON(http.StatusConflict, gin.H{"error": "model is still used by a model route"})
		return
	}
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
	if input.DailyEventMin < 8 || input.DailyEventMax < input.DailyEventMin || input.DailyEventMax > 15 ||
		input.DailyProactiveLimit < 0 || input.DailyProactiveLimit > 8 ||
		input.DailyLifePhotoLimit < 0 || input.DailyLifePhotoLimit > 4 ||
		input.QuietHoursStart < 0 || input.QuietHoursStart > 23 || input.QuietHoursEnd < 0 || input.QuietHoursEnd > 23 ||
		input.FreeDefaultChatHours < 1 || input.FreeDefaultChatHours > 720 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid agent limits"})
		return
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save agent settings"})
		return
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(c.Request.Context(), `
		UPDATE agent_settings SET daily_event_min=$1,daily_event_max=$2,daily_proactive_limit=$3,daily_life_photo_limit=$4,
		quiet_hours_start=$5,quiet_hours_end=$6,free_default_chat_hours=$7,updated_at=CURRENT_TIMESTAMP WHERE id='default'`,
		input.DailyEventMin, input.DailyEventMax, input.DailyProactiveLimit, input.DailyLifePhotoLimit, input.QuietHoursStart, input.QuietHoursEnd, input.FreeDefaultChatHours)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save agent settings"})
		return
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save agent settings"})
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
	IsDefault       bool     `json:"is_default"`
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
		_, err = db.Get().Exec(`INSERT INTO companion_portraits (id,name,image_url,gender,personality_tags,is_default,enabled,sort_order) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
			id, input.Name, input.ImageURL, input.Gender, tags, input.IsDefault, enabled, input.SortOrder)
	} else {
		_, err = db.Get().Exec(`UPDATE companion_portraits SET name=$2,image_url=$3,gender=$4,personality_tags=$5,is_default=$6,enabled=$7,sort_order=$8,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
			id, input.Name, input.ImageURL, input.Gender, tags, input.IsDefault, enabled, input.SortOrder)
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

type pushTokenInput struct {
	Token    string `json:"token" binding:"required"`
	Platform string `json:"platform" binding:"required"`
	DeviceID string `json:"device_id"`
	Locale   string `json:"locale"`
}

func RegisterPushToken(c *gin.Context) {
	var input pushTokenInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Token = strings.TrimSpace(input.Token)
	input.Platform = strings.ToLower(strings.TrimSpace(input.Platform))
	if input.Token == "" || len(input.Token) > 4096 || (input.Platform != "ios" && input.Platform != "android") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid push token or platform"})
		return
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register push token"})
		return
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(c.Request.Context(), `
		INSERT INTO device_push_tokens (id,user_id,token,platform,device_id,locale,enabled,last_seen_at)
		VALUES ($1,$2,$3,$4,$5,$6,true,CURRENT_TIMESTAMP)
		ON CONFLICT (token) DO UPDATE SET user_id=EXCLUDED.user_id,platform=EXCLUDED.platform,
		device_id=EXCLUDED.device_id,locale=EXCLUDED.locale,enabled=true,
		last_seen_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP`,
		uuid.New().String(), c.GetString("user_id"), input.Token, input.Platform,
		strings.TrimSpace(input.DeviceID), strings.TrimSpace(input.Locale))
	if err == nil {
		_, err = tx.ExecContext(c.Request.Context(), `UPDATE users SET preferred_locale=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2`, language.Normalize(input.Locale), c.GetString("user_id"))
	}
	if err == nil {
		_, err = tx.ExecContext(c.Request.Context(), `
			UPDATE notification_outbox SET available_at=CURRENT_TIMESTAMP,last_error=''
			WHERE user_id=$1 AND channel='push' AND status='ready'
			  AND created_at >= CURRENT_TIMESTAMP - INTERVAL '6 hours'`, c.GetString("user_id"))
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register push token"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"registered": true})
}

func UnregisterPushToken(c *gin.Context) {
	var input struct {
		Token string `json:"token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	_, err := db.Get().ExecContext(c.Request.Context(), `
		UPDATE device_push_tokens SET enabled=false,updated_at=CURRENT_TIMESTAMP
		WHERE user_id=$1 AND token=$2`, c.GetString("user_id"), strings.TrimSpace(input.Token))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to unregister push token"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"registered": false})
}

type adminCompanionInput struct {
	UserID            string          `json:"user_id"`
	Name              string          `json:"name" binding:"required"`
	Gender            string          `json:"gender"`
	Persona           string          `json:"persona"`
	City              string          `json:"city"`
	Occupation        string          `json:"occupation"`
	Interests         string          `json:"interests"`
	RelationshipStage string          `json:"relationship_stage"`
	PersonalityTags   []string        `json:"personality_tags"`
	SpeakingStyle     string          `json:"speaking_style"`
	Likes             string          `json:"likes"`
	Dislikes          string          `json:"dislikes"`
	LifeHabits        string          `json:"life_habits"`
	LifeGoal          string          `json:"life_goal"`
	Backstory         string          `json:"backstory"`
	PortraitID        *string         `json:"portrait_id"`
	ModelID           *string         `json:"model_id"`
	ProactiveEnabled  *bool           `json:"proactive_enabled"`
	Active            *bool           `json:"active"`
	VoiceEnabled      *bool           `json:"voice_enabled"`
	VoiceConfig       json.RawMessage `json:"voice_config"`
}

func AdminListCompanions(c *gin.Context) {
	rows, err := db.Get().Query(`
		SELECT c.id,c.user_id,u.email,c.name,COALESCE(c.gender,''),COALESCE(c.persona,''),COALESCE(c.city,''),COALESCE(c.occupation,''),
		COALESCE(c.interests,''),COALESCE(c.relationship_stage,'stranger'),c.personality_tags::text,c.speaking_style,c.likes,c.dislikes,
		c.life_habits,c.life_goal,c.backstory,c.model_id,c.portrait_id,c.proactive_enabled,c.active,c.voice_enabled,c.voice_config::text,c.created_at,c.updated_at
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
		var proactive, active, voiceEnabled bool
		var voiceConfig json.RawMessage
		var created, updated time.Time
		if err := rows.Scan(&id, &userID, &email, &name, &gender, &persona, &city, &occupation, &interests, &relationshipStage, &tags, &speakingStyle, &likes, &dislikes, &lifeHabits, &lifeGoal, &backstory, &modelID, &portraitID, &proactive, &active, &voiceEnabled, &voiceConfig, &created, &updated); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read companions"})
			return
		}
		items = append(items, gin.H{"id": id, "user_id": userID, "user_email": email, "name": name, "gender": gender, "persona": persona, "city": city, "occupation": occupation, "interests": interests, "relationship_stage": relationshipStage, "personality_tags": tags, "speaking_style": speakingStyle, "likes": likes, "dislikes": dislikes, "life_habits": lifeHabits, "life_goal": lifeGoal, "backstory": backstory, "model_id": nullString(modelID), "portrait_id": nullString(portraitID), "proactive_enabled": proactive, "active": active, "voice_enabled": voiceEnabled, "voice_config": voiceConfig, "created_at": created, "updated_at": updated})
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
	if len(input.VoiceConfig) > 0 && !json.Valid(input.VoiceConfig) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "voice_config must be valid JSON"})
		return
	}
	if input.RelationshipStage == "" {
		input.RelationshipStage = "stranger"
	}
	if input.ModelID != nil {
		modelID := strings.TrimSpace(*input.ModelID)
		if modelID == "" {
			input.ModelID = nil
		} else {
			var valid bool
			if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM ai_models WHERE id=$1 AND enabled=true AND capabilities ? 'text' AND configured_scenarios ? 'text_chat')`, modelID).Scan(&valid); err != nil || !valid {
				c.JSON(http.StatusBadRequest, gin.H{"error": "companion model must be enabled and configured for text_chat"})
				return
			}
			input.ModelID = &modelID
		}
	}
	if id == "" {
		voiceEnabled := false
		if input.VoiceEnabled != nil {
			voiceEnabled = *input.VoiceEnabled
		}
		voiceConfig := input.VoiceConfig
		if len(voiceConfig) == 0 {
			voiceConfig = json.RawMessage(`{}`)
		}
		id = uuid.New().String()
		tx, err := db.Get().Begin()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create companion"})
			return
		}
		defer tx.Rollback()
		_, err = tx.Exec(`INSERT INTO companions (id,user_id,name,gender,persona,city,occupation,interests,relationship_stage,personality_tags,speaking_style,likes,dislikes,life_habits,life_goal,backstory,portrait_id,model_id,creation_source,proactive_enabled,active,voice_enabled,voice_config) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,'admin',$19,$20,$21,$22)`,
			id, input.UserID, input.Name, input.Gender, input.Persona, input.City, input.Occupation, input.Interests, input.RelationshipStage, tags, input.SpeakingStyle, input.Likes, input.Dislikes, input.LifeHabits, input.LifeGoal, input.Backstory, input.PortraitID, input.ModelID, proactive, active, voiceEnabled, voiceConfig)
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
		var voiceConfig any
		if len(input.VoiceConfig) > 0 {
			voiceConfig = input.VoiceConfig
		}
		result, err := db.Get().Exec(`UPDATE companions SET name=$2,gender=$3,persona=$4,city=$5,occupation=$6,interests=$7,relationship_stage=$8,personality_tags=$9,speaking_style=$10,likes=$11,dislikes=$12,life_habits=$13,life_goal=$14,backstory=$15,portrait_id=$16,model_id=$17,proactive_enabled=$18,active=$19,voice_enabled=COALESCE($20,voice_enabled),voice_config=COALESCE($21,voice_config),updated_at=CURRENT_TIMESTAMP WHERE id=$1`,
			id, input.Name, input.Gender, input.Persona, input.City, input.Occupation, input.Interests, input.RelationshipStage, tags, input.SpeakingStyle, input.Likes, input.Dislikes, input.LifeHabits, input.LifeGoal, input.Backstory, input.PortraitID, input.ModelID, proactive, active, input.VoiceEnabled, voiceConfig)
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
	rows, err := db.Get().Query(`SELECT m.id,m.provider_id,p.name,m.model_name,m.display_name,m.capabilities::text,m.configured_scenarios::text,m.enabled,m.created_at,m.updated_at FROM ai_models m JOIN ai_providers p ON p.id=m.provider_id ORDER BY m.created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]adminModel, 0)
	for rows.Next() {
		var item adminModel
		var raw, configuredRaw string
		if err := rows.Scan(&item.ID, &item.ProviderID, &item.ProviderName, &item.ModelName, &item.DisplayName, &raw, &configuredRaw, &item.Enabled, &item.CreatedAt, &item.UpdatedAt); err != nil {
			return nil, err
		}
		item.Capabilities = json.RawMessage(raw)
		item.ConfiguredScenarios = json.RawMessage(configuredRaw)
		items = append(items, item)
	}
	return items, rows.Err()
}

func loadAgentSettings() (agentSettingsResponse, error) {
	var output agentSettingsResponse
	var chat, life, proactive, image, transcription, speech sql.NullString
	err := db.Get().QueryRow(`SELECT chat_model_id,life_model_id,proactive_model_id,image_model_id,transcription_model_id,speech_model_id,daily_event_min,daily_event_max,daily_proactive_limit,daily_life_photo_limit,quiet_hours_start,quiet_hours_end,free_default_chat_hours FROM agent_settings WHERE id='default'`).Scan(&chat, &life, &proactive, &image, &transcription, &speech, &output.DailyEventMin, &output.DailyEventMax, &output.DailyProactiveLimit, &output.DailyLifePhotoLimit, &output.QuietHoursStart, &output.QuietHoursEnd, &output.FreeDefaultChatHours)
	output.ChatModelID = nullString(chat)
	output.LifeModelID = nullString(life)
	output.ProactiveModelID = nullString(proactive)
	output.ImageModelID = nullString(image)
	output.TranscriptionModelID = nullString(transcription)
	output.SpeechModelID = nullString(speech)
	return output, err
}

func loadPortraits(enabledOnly bool) ([]portraitResponse, error) {
	query := `SELECT id,name,image_url,gender,personality_tags::text,is_default,enabled,sort_order FROM companion_portraits`
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
		if err := rows.Scan(&item.ID, &item.Name, &item.ImageURL, &item.Gender, &raw, &item.IsDefault, &item.Enabled, &item.SortOrder); err != nil {
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

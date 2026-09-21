package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lib/pq"

	"vita/internal/credits"
	"vita/internal/db"
)

type aiPetBreedInput struct {
	Environment         string   `json:"environment" binding:"required,oneof=dev beta prod"`
	Name                string   `json:"name" binding:"required"`
	Species             string   `json:"species" binding:"required"`
	Personality         string   `json:"personality"`
	Description         string   `json:"description"`
	AvatarURL           string   `json:"avatar_url"`
	SortOrder           int      `json:"sort_order"`
	Enabled             bool     `json:"enabled"`
	SubscriptionPlanIDs []string `json:"subscription_plan_ids"`
}

type aiPetBreed struct {
	ID                   string   `json:"id"`
	Environment          string   `json:"environment"`
	Name                 string   `json:"name"`
	Species              string   `json:"species"`
	Personality          string   `json:"personality"`
	Description          string   `json:"description"`
	AvatarURL            string   `json:"avatar_url"`
	SortOrder            int      `json:"sort_order"`
	Enabled              bool     `json:"enabled"`
	SubscriptionPlanIDs  []string `json:"subscription_plan_ids"`
	CanAdopt             bool     `json:"can_adopt,omitempty"`
	AdoptedCompanionID   string   `json:"adopted_companion_id,omitempty"`
	AdoptedCompanionName string   `json:"adopted_companion_name,omitempty"`
}

func AdminListAIPetBreeds(c *gin.Context) {
	environment := strings.TrimSpace(c.DefaultQuery("environment", currentEnvironment()))
	rows, err := db.Get().Query(`SELECT b.id,b.environment,b.name,b.species,b.personality,b.description,b.avatar_url,b.sort_order,b.enabled,
		COALESCE(jsonb_agg(link.subscription_plan_id ORDER BY link.subscription_plan_id) FILTER (WHERE link.subscription_plan_id IS NOT NULL),'[]'::jsonb)::text
		FROM ai_pet_breeds b LEFT JOIN ai_pet_breed_subscription_plans link ON link.breed_id=b.id
		WHERE b.environment=$1 GROUP BY b.id ORDER BY b.sort_order,b.name`, environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load AI pet breeds"})
		return
	}
	defer rows.Close()
	items := []aiPetBreed{}
	for rows.Next() {
		var item aiPetBreed
		var plans string
		if err := rows.Scan(&item.ID, &item.Environment, &item.Name, &item.Species, &item.Personality, &item.Description, &item.AvatarURL, &item.SortOrder, &item.Enabled, &plans); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read AI pet breeds"})
			return
		}
		_ = json.Unmarshal([]byte(plans), &item.SubscriptionPlanIDs)
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read AI pet breeds"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminCreateAIPetBreed(c *gin.Context) {
	saveAIPetBreed(c, uuid.New().String(), true)
}

func AdminUpdateAIPetBreed(c *gin.Context) {
	saveAIPetBreed(c, c.Param("id"), false)
}

func saveAIPetBreed(c *gin.Context, id string, create bool) {
	var input aiPetBreedInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Name = strings.TrimSpace(input.Name)
	input.Species = strings.TrimSpace(input.Species)
	input.Personality = strings.TrimSpace(input.Personality)
	input.Description = strings.TrimSpace(input.Description)
	input.AvatarURL = strings.TrimSpace(input.AvatarURL)
	input.SubscriptionPlanIDs = uniqueStrings(input.SubscriptionPlanIDs)
	if input.Name == "" || input.Species == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name and species are required"})
		return
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save AI pet breed"})
		return
	}
	defer tx.Rollback()
	if len(input.SubscriptionPlanIDs) > 0 {
		var count int
		if err := tx.QueryRow(`SELECT COUNT(*) FROM subscription_plans WHERE environment=$1 AND id=ANY($2)`, input.Environment, pq.Array(input.SubscriptionPlanIDs)).Scan(&count); err != nil || count != len(input.SubscriptionPlanIDs) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "subscription plans must exist in the selected environment"})
			return
		}
	}
	if create {
		_, err = tx.Exec(`INSERT INTO ai_pet_breeds(id,environment,name,species,personality,description,avatar_url,sort_order,enabled)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, id, input.Environment, input.Name, input.Species, input.Personality, input.Description, input.AvatarURL, input.SortOrder, input.Enabled)
	} else {
		var result sql.Result
		result, err = tx.Exec(`UPDATE ai_pet_breeds SET environment=$2,name=$3,species=$4,personality=$5,description=$6,avatar_url=$7,sort_order=$8,enabled=$9,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, id, input.Environment, input.Name, input.Species, input.Personality, input.Description, input.AvatarURL, input.SortOrder, input.Enabled)
		if err == nil {
			if count, _ := result.RowsAffected(); count == 0 {
				c.JSON(http.StatusNotFound, gin.H{"error": "AI pet breed not found"})
				return
			}
		}
	}
	if err == nil {
		_, err = tx.Exec(`DELETE FROM ai_pet_breed_subscription_plans WHERE breed_id=$1`, id)
	}
	for _, planID := range input.SubscriptionPlanIDs {
		if err == nil {
			_, err = tx.Exec(`INSERT INTO ai_pet_breed_subscription_plans(breed_id,subscription_plan_id) VALUES($1,$2)`, id, planID)
		}
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to save AI pet breed"})
		return
	}
	c.JSON(map[bool]int{true: http.StatusCreated, false: http.StatusOK}[create], aiPetBreed{ID: id, Environment: input.Environment, Name: input.Name, Species: input.Species, Personality: input.Personality, Description: input.Description, AvatarURL: input.AvatarURL, SortOrder: input.SortOrder, Enabled: input.Enabled, SubscriptionPlanIDs: input.SubscriptionPlanIDs})
}

func ListAIPetBreeds(c *gin.Context) {
	userID := c.GetString("user_id")
	rows, err := db.Get().Query(`SELECT b.id,b.environment,b.name,b.species,b.personality,b.description,b.avatar_url,b.sort_order,b.enabled,
		COALESCE((SELECT c.id FROM companions c WHERE c.user_id=$1 AND c.pet_breed_id=b.id AND c.deleted_at IS NULL LIMIT 1),''),
		COALESCE((SELECT c.name FROM companions c WHERE c.user_id=$1 AND c.pet_breed_id=b.id AND c.deleted_at IS NULL LIMIT 1),''),
		(EXISTS(SELECT 1 FROM subscriptions s WHERE s.user_id=$1 AND s.status='active' AND (s.current_period_end IS NULL OR s.current_period_end>CURRENT_TIMESTAMP)) AND
		 (NOT EXISTS(SELECT 1 FROM ai_pet_breed_subscription_plans link WHERE link.breed_id=b.id) OR EXISTS(
			SELECT 1 FROM ai_pet_breed_subscription_plans link JOIN subscription_plans p ON p.id=link.subscription_plan_id
			JOIN subscriptions s ON s.user_id=$1 AND s.environment=p.environment AND s.platform=p.platform AND s.product_id=p.product_id
			WHERE link.breed_id=b.id AND s.status='active' AND (s.current_period_end IS NULL OR s.current_period_end>CURRENT_TIMESTAMP))))
		FROM ai_pet_breeds b WHERE b.environment=$2 AND b.enabled=true ORDER BY b.sort_order,b.name`, userID, currentEnvironment())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load AI pets"})
		return
	}
	defer rows.Close()
	items := []aiPetBreed{}
	for rows.Next() {
		var item aiPetBreed
		if err := rows.Scan(&item.ID, &item.Environment, &item.Name, &item.Species, &item.Personality, &item.Description, &item.AvatarURL, &item.SortOrder, &item.Enabled, &item.AdoptedCompanionID, &item.AdoptedCompanionName, &item.CanAdopt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read AI pets"})
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read AI pets"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdoptAIPet(c *gin.Context) {
	var input struct {
		BreedID string `json:"breed_id" binding:"required"`
		Name    string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Name = strings.TrimSpace(input.Name)
	if input.Name == "" || len([]rune(input.Name)) > 40 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "pet name must be between 1 and 40 characters"})
		return
	}
	userID := c.GetString("user_id")
	var breed aiPetBreed
	var canAdopt bool
	err := db.Get().QueryRow(`SELECT b.id,b.name,b.species,b.personality,b.description,b.avatar_url,
		(EXISTS(SELECT 1 FROM subscriptions s WHERE s.user_id=$1 AND s.status='active' AND (s.current_period_end IS NULL OR s.current_period_end>CURRENT_TIMESTAMP)) AND
		 (NOT EXISTS(SELECT 1 FROM ai_pet_breed_subscription_plans link WHERE link.breed_id=b.id) OR EXISTS(
			SELECT 1 FROM ai_pet_breed_subscription_plans link JOIN subscription_plans p ON p.id=link.subscription_plan_id
			JOIN subscriptions s ON s.user_id=$1 AND s.environment=p.environment AND s.platform=p.platform AND s.product_id=p.product_id
			WHERE link.breed_id=b.id AND s.status='active' AND (s.current_period_end IS NULL OR s.current_period_end>CURRENT_TIMESTAMP))))
		FROM ai_pet_breeds b WHERE b.id=$2 AND b.environment=$3 AND b.enabled=true`, userID, input.BreedID, currentEnvironment()).Scan(
		&breed.ID, &breed.Name, &breed.Species, &breed.Personality, &breed.Description, &breed.AvatarURL, &canAdopt)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "AI pet breed not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check AI pet breed"})
		return
	}
	if !canAdopt {
		subscriptionRequired(c, "ai_pet_plan_required", "Your current subscription cannot adopt this pet")
		return
	}
	companionID := uuid.New().String()
	tags := strings.FieldsFunc(breed.Personality, func(r rune) bool { return r == ',' || r == '，' || r == '·' })
	if len(tags) > 8 {
		tags = tags[:8]
	}
	encodedTags, _ := json.Marshal(tags)
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to adopt AI pet"})
		return
	}
	defer tx.Rollback()
	if err == nil {
		_, err = tx.Exec(`INSERT INTO companions(id,user_id,name,gender,persona,appearance,occupation,interests,relationship_stage,
			personality_tags,speaking_style,likes,life_habits,life_goal,backstory,creation_source,proactive_enabled,active,is_default,life_enabled,friendship_active,pet_breed_id,avatar_url)
			VALUES($1,$2,$3,'pet',$4,$5,'AI Pet','playing, treats','acquaintance',$6,'simple and affectionate','attention and treats','daily naps and play','grow together',$7,'ai_pet',true,true,false,true,true,$8,$9)`,
			companionID, userID, input.Name, breed.Description, breed.Species, encodedTags, breed.Personality, breed.ID, breed.AvatarURL)
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO relationship_states(companion_id) VALUES($1)`, companionID)
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO companion_states(companion_id,mood,energy,stress,social_energy) VALUES($1,75,80,10,70)`, companionID)
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO ai_pet_states(companion_id) VALUES($1)`, companionID)
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata) VALUES($1,$2,'milestone',$3,100,CURRENT_TIMESTAMP,$4)`,
			uuid.New().String(), companionID, "Adoption day: "+input.Name+" joined the family.", `{"source":"ai_pet_adoption"}`)
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO life_events(id,companion_id,event_type,title,description,start_time,end_time,emotion,importance,user_relevance,shareability,status,local_date,sequence,payload,generation_source)
			VALUES($1,$2,'milestone','A new home',$3,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP + INTERVAL '30 minutes','happy',100,100,true,'active',CURRENT_DATE,0,$4,'system')`,
			uuid.New().String(), companionID, input.Name+" was adopted today.", `{"source":"ai_pet_adoption"}`)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "this pet has already been adopted or could not be created"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"companion_id": companionID, "name": input.Name, "breed": breed, "state": petStateResponse{Hunger: 80, Happiness: 70, Energy: 80, Health: 100, Experience: 0, Level: 1}})
}

type petStateResponse struct {
	Hunger     int        `json:"hunger"`
	Happiness  int        `json:"happiness"`
	Energy     int        `json:"energy"`
	Health     int        `json:"health"`
	Experience int        `json:"experience"`
	Level      int        `json:"level"`
	LastFedAt  *time.Time `json:"last_fed_at"`
	Coins      int        `json:"coins"`
	FeedCoins  int        `json:"feed_coin_cost"`
}

func GetAIPetState(c *gin.Context) {
	state, err := loadAndDecayPetState(c.Request.Context(), c.GetString("user_id"), c.Param("id"))
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "AI pet not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load AI pet"})
		return
	}
	c.JSON(http.StatusOK, state)
}

func FeedAIPet(c *gin.Context) {
	var input struct {
		IdempotencyKey string `json:"idempotency_key" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	ctx := c.Request.Context()
	userID, companionID := c.GetString("user_id"), c.Param("id")
	if _, err := loadAndDecayPetState(ctx, userID, companionID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "AI pet not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load AI pet"})
		}
		return
	}
	reservation, err := credits.Reserve(ctx, db.Get(), credits.ReserveParams{UserID: userID, CompanionID: companionID, Environment: currentEnvironment(), Platform: requestPlatform(c), ProductKey: "ai_pet_feed", IdempotencyKey: input.IdempotencyKey, ReferenceType: "ai_pet_feed"})
	if err != nil {
		writeSpendError(c, err)
		return
	}
	if reservation.Idempotent {
		c.JSON(http.StatusOK, gin.H{"balance": reservation.Balance, "state": reservation.Result, "idempotent": true})
		return
	}
	var state petStateResponse
	var lastFed time.Time
	err = db.Get().QueryRowContext(ctx, `UPDATE ai_pet_states s SET hunger=LEAST(100,hunger+25),happiness=LEAST(100,happiness+8),energy=LEAST(100,energy+4),
		experience=experience+20,level=1+((experience+20)/100),last_fed_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP
		FROM companions c WHERE s.companion_id=c.id AND c.id=$1 AND c.user_id=$2 AND c.creation_source='ai_pet'
		RETURNING s.hunger,s.happiness,s.energy,s.health,s.experience,s.level,s.last_fed_at`, companionID, userID).Scan(
		&state.Hunger, &state.Happiness, &state.Energy, &state.Health, &state.Experience, &state.Level, &lastFed)
	if err != nil {
		settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = credits.Refund(settlementCtx, db.Get(), reservation.ID, err.Error())
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to feed AI pet", "refunded": true})
		return
	}
	state.LastFedAt = &lastFed
	state.Coins = reservation.Balance
	state.FeedCoins = reservation.Product.Coins
	result, _ := json.Marshal(state)
	var resultMap map[string]any
	_ = json.Unmarshal(result, &resultMap)
	settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := credits.Complete(settlementCtx, db.Get(), reservation.ID, companionID, resultMap); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "pet was fed but settlement could not be recorded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"balance": reservation.Balance, "coins": reservation.Product.Coins, "state": state})
}

func loadAndDecayPetState(ctx context.Context, userID, companionID string) (petStateResponse, error) {
	var state petStateResponse
	var lastDecay time.Time
	var lastFed sql.NullTime
	err := db.Get().QueryRowContext(ctx, `SELECT s.hunger,s.happiness,s.energy,s.health,s.experience,s.level,s.last_fed_at,s.last_decay_at,u.credits_balance,
		COALESCE((SELECT p.coins FROM credit_products p WHERE p.environment=u.environment AND p.product_key='ai_pet_feed' AND p.enabled=true),5)
		FROM ai_pet_states s JOIN companions c ON c.id=s.companion_id JOIN users u ON u.id=c.user_id
		WHERE c.id=$1 AND c.user_id=$2 AND c.active=true AND c.creation_source='ai_pet'`, companionID, userID).Scan(
		&state.Hunger, &state.Happiness, &state.Energy, &state.Health, &state.Experience, &state.Level, &lastFed, &lastDecay, &state.Coins, &state.FeedCoins)
	if err != nil {
		return state, err
	}
	now := time.Now().UTC()
	updated, hours := decayPetState(state, lastDecay, now)
	if hours > 0 {
		_, err = db.Get().ExecContext(ctx, `UPDATE ai_pet_states SET hunger=$2,happiness=$3,energy=$4,health=$5,last_decay_at=$6,updated_at=CURRENT_TIMESTAMP WHERE companion_id=$1`, companionID, updated.Hunger, updated.Happiness, updated.Energy, updated.Health, lastDecay.Add(time.Duration(hours)*time.Hour))
		if err != nil {
			return state, err
		}
		state = updated
	}
	state.LastFedAt = nullTime(lastFed)
	return state, nil
}

func decayPetState(state petStateResponse, lastDecay, now time.Time) (petStateResponse, int) {
	hours := int(now.Sub(lastDecay).Hours())
	if hours <= 0 {
		return state, 0
	}
	if hours > 72 {
		hours = 72
	}
	state.Hunger = clampPetValue(state.Hunger - hours*2)
	state.Happiness = clampPetValue(state.Happiness - hours)
	state.Energy = clampPetValue(state.Energy - hours/2)
	if state.Hunger < 20 {
		state.Health = clampPetValue(state.Health - hours/3)
	}
	return state, hours
}

func clampPetValue(value int) int {
	if value < 0 {
		return 0
	}
	if value > 100 {
		return 100
	}
	return value
}

func uniqueStrings(values []string) []string {
	seen := map[string]bool{}
	result := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" && !seen[value] {
			seen[value] = true
			result = append(result, value)
		}
	}
	return result
}

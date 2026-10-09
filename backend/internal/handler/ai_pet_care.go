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

	"vita/internal/db"
)

var petCareCooldown = map[string]time.Duration{
	"pet":   5 * time.Minute,
	"drink": 5 * time.Minute,
	"walk":  10 * time.Minute,
	"rest":  10 * time.Minute,
}

// CareForAIPet persists the outcome of an interaction. Locking the pet state
// serializes concurrent actions and makes request-key retries idempotent.
func CareForAIPet(c *gin.Context) {
	var input struct {
		Kind           string `json:"kind" binding:"required"`
		IdempotencyKey string `json:"idempotency_key" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Kind = strings.TrimSpace(input.Kind)
	input.IdempotencyKey = strings.TrimSpace(input.IdempotencyKey)
	cooldown, valid := petCareCooldown[input.Kind]
	if !valid || len(input.IdempotencyKey) == 0 || len(input.IdempotencyKey) > 128 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid pet care action"})
		return
	}
	ctx := c.Request.Context()
	userID, companionID := c.GetString("user_id"), c.Param("id")
	initialState, err := loadAndDecayPetState(ctx, userID, companionID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "AI pet not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load AI pet"})
		}
		return
	}
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to begin pet care"})
		return
	}
	defer tx.Rollback()
	state := initialState
	var lastEvent time.Time
	err = tx.QueryRowContext(ctx, `SELECT s.hunger,s.hydration,s.happiness,s.energy,s.health,s.experience,s.level
		FROM ai_pet_states s JOIN companions c ON c.id=s.companion_id
		WHERE c.id=$1 AND c.user_id=$2 AND c.active=true AND c.creation_source='ai_pet'
		FOR UPDATE OF s`, companionID, userID).Scan(
		&state.Hunger, &state.Hydration, &state.Happiness, &state.Energy,
		&state.Health, &state.Experience, &state.Level)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "AI pet not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to lock pet state"})
		}
		return
	}
	requestKey := "pet_care:" + companionID + ":" + input.IdempotencyKey
	var previous []byte
	var previousKind string
	err = tx.QueryRowContext(ctx, `SELECT kind,result FROM ai_pet_care_events WHERE user_id=$1 AND request_key=$2`, userID, requestKey).Scan(&previousKind, &previous)
	if err == nil {
		if previousKind != input.Kind {
			c.JSON(http.StatusConflict, gin.H{"error": "pet care request key was used for a different action"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"state": json.RawMessage(previous), "idempotent": true})
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check pet care request"})
		return
	}
	err = tx.QueryRowContext(ctx, `SELECT created_at FROM ai_pet_care_events
		WHERE companion_id=$1 AND kind=$2 ORDER BY created_at DESC LIMIT 1`, companionID, input.Kind).Scan(&lastEvent)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check pet care cooldown"})
		return
	}
	if err == nil && time.Since(lastEvent) < cooldown {
		retryAfter := int((cooldown - time.Since(lastEvent)).Seconds()) + 1
		c.JSON(http.StatusTooManyRequests, gin.H{"code": "pet_care_cooldown", "error": "pet care action is cooling down", "retry_after_seconds": retryAfter})
		return
	}
	if !applyPetCare(&state, input.Kind) {
		c.JSON(http.StatusConflict, gin.H{"code": "pet_needs_rest", "error": "pet needs rest or water before a walk"})
		return
	}
	_, err = tx.ExecContext(ctx, `UPDATE ai_pet_states SET hunger=$2,hydration=$3,happiness=$4,energy=$5,
		health=$6,experience=$7,level=$8,updated_at=CURRENT_TIMESTAMP WHERE companion_id=$1`,
		companionID, state.Hunger, state.Hydration, state.Happiness, state.Energy,
		state.Health, state.Experience, state.Level)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update pet state"})
		return
	}
	result, err := json.Marshal(state)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to encode pet state"})
		return
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO ai_pet_care_events(id,user_id,companion_id,kind,request_key,result)
		VALUES($1,$2,$3,$4,$5,$6::jsonb)`, uuid.New().String(), userID, companionID,
		input.Kind, requestKey, string(result))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record pet care"})
		return
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save pet care"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"state": state})
}

// applyPetCare returns false when a walk cannot safely start.
func applyPetCare(state *petStateResponse, kind string) bool {
	switch kind {
	case "pet":
		state.Happiness = clampPetValue(state.Happiness + 3)
		state.Experience++
	case "drink":
		state.Hydration = clampPetValue(state.Hydration + 30)
		state.Energy = clampPetValue(state.Energy + 2)
		state.Experience += 2
	case "walk":
		if state.Energy < 15 || state.Hydration < 10 {
			return false
		}
		state.Hunger = clampPetValue(state.Hunger - 5)
		state.Hydration = clampPetValue(state.Hydration - 6)
		state.Energy = clampPetValue(state.Energy - 12)
		state.Happiness = clampPetValue(state.Happiness + 12)
		state.Experience += 10
	case "rest":
		state.Energy = clampPetValue(state.Energy + 20)
		state.Health = clampPetValue(state.Health + 2)
		state.Experience += 2
	}
	state.Level = 1 + state.Experience/100
	return true
}

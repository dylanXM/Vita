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

	"vita/internal/credits"
	"vita/internal/db"
)

// A date request is recorded before the companion decides whether the time fits.
// No credits are reserved until the companion has accepted the invitation.
func requestCompanionDate(c *gin.Context, userID, companionID, productKey string, input experienceRequest) {
	ctx := c.Request.Context()
	var product credits.Product
	var metadataRaw string
	err := db.Get().QueryRowContext(ctx, `SELECT product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata::text
		FROM credit_products WHERE environment=$1 AND product_key=$2 AND category='date' AND enabled=true`,
		currentEnvironment(), productKey).Scan(&product.Key, &product.Category, &product.NameKey,
		&product.DescriptionKey, &product.Emoji, &product.Coins, &product.Enabled, &product.SortOrder, &metadataRaw)
	if errors.Is(err, sql.ErrNoRows) {
		writeSpendError(c, credits.ErrProductNotFound)
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load date"})
		return
	}
	if err := json.Unmarshal([]byte(metadataRaw), &product.Metadata); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "invalid date configuration"})
		return
	}
	start, err := requestedDateTime(input.Input)
	if err != nil {
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": err.Error(), "code": "invalid_appointment"})
		return
	}
	requestID := uuid.New().String()
	inserted, err := db.Get().ExecContext(ctx, `INSERT INTO companion_date_requests
		(id,user_id,companion_id,product_key,idempotency_key,scheduled_at,status)
		VALUES($1,$2,$3,$4,$5,$6,'requested') ON CONFLICT(user_id,idempotency_key) DO NOTHING`,
		requestID, userID, companionID, productKey, input.IdempotencyKey, start)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save date request"})
		return
	}
	count, _ := inserted.RowsAffected()
	if count == 0 {
		var existingID, existingProduct, status, reason, resultRaw string
		err := db.Get().QueryRowContext(ctx, `SELECT id,product_key,status,reason,result::text
			FROM companion_date_requests WHERE user_id=$1 AND idempotency_key=$2`, userID, input.IdempotencyKey).
			Scan(&existingID, &existingProduct, &status, &reason, &resultRaw)
		if err != nil || existingProduct != productKey {
			c.JSON(http.StatusConflict, gin.H{"error": "date request key already used", "code": "invalid_request"})
			return
		}
		var result map[string]any
		_ = json.Unmarshal([]byte(resultRaw), &result)
		if result == nil {
			result = map[string]any{}
		}
		if status == "requested" {
			var settledRaw string
			settledErr := db.Get().QueryRowContext(ctx, `SELECT result::text FROM credit_spends
				WHERE user_id=$1 AND idempotency_key=$2 AND status='completed'`,
				userID, "date-"+existingID).Scan(&settledRaw)
			if settledErr == nil {
				_ = json.Unmarshal([]byte(settledRaw), &result)
				if eventID, ok := result["event_id"].(string); ok && eventID != "" {
					_, _ = db.Get().ExecContext(ctx, `UPDATE companion_date_requests SET status='accepted',event_id=$2,
						result=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND status='requested'`,
						existingID, eventID, jsonValue(result))
					status = "accepted"
				}
			}
		}
		if result == nil {
			result = map[string]any{}
		}
		result["status"] = status
		result["reason"] = reason
		if status == "declined" {
			c.JSON(http.StatusConflict, gin.H{"error": "companion declined this time", "code": "date_declined", "reason": reason})
			return
		}
		if status != "accepted" {
			c.JSON(http.StatusConflict, gin.H{"error": "date request is not confirmed", "code": "date_request_pending", "reason": reason})
			return
		}
		var balance int
		_ = db.Get().QueryRowContext(ctx, `SELECT credits_balance FROM users WHERE id=$1`, userID).Scan(&balance)
		c.JSON(http.StatusOK, gin.H{"product": product, "balance": balance, "result": result, "idempotent": true})
		return
	}

	duration := time.Duration(metadataInt(product.Metadata, "duration_minutes", 60)) * time.Minute
	if companionAgent == nil {
		failDateRequest(requestID)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "companion service unavailable", "code": "date_decision_failed"})
		return
	}
	status, err := companionAgent.CurrentStatus(ctx, companionID, userID)
	if err != nil {
		failDateRequest(requestID)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "companion could not consider the invitation", "code": "date_decision_failed"})
		return
	}
	available, err := nextAvailableExperienceTime(ctx, companionID, start, duration)
	if err != nil {
		failDateRequest(requestID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check companion schedule"})
		return
	}
	if (status.Busy && status.AvailableAt != nil && status.AvailableAt.After(start)) || !available.Equal(start) {
		result := map[string]any{"status": "declined", "reason": "schedule_conflict", "scheduled_at": start}
		_, err = db.Get().ExecContext(ctx, `UPDATE companion_date_requests SET status='declined',reason='schedule_conflict',
			result=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, requestID, jsonValue(result))
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record companion response"})
			return
		}
		c.JSON(http.StatusConflict, gin.H{"error": "companion declined this time", "code": "date_declined", "reason": "schedule_conflict"})
		return
	}
	conversationID, err := experienceConversation(ctx, userID, companionID)
	if err != nil {
		failDateRequest(requestID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to open conversation"})
		return
	}
	location, _ := product.Metadata["location"].(string)
	reaction, err := companionAgent.ComposeMomentInvitation(ctx, conversationID, userID, product.NameKey, location, start)
	if err != nil || strings.TrimSpace(reaction) == "" {
		failDateRequest(requestID)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "companion could not respond to the invitation", "code": "date_decision_failed"})
		return
	}
	reservation, err := credits.Reserve(ctx, db.Get(), credits.ReserveParams{
		UserID: userID, CompanionID: companionID, Environment: currentEnvironment(), Platform: requestPlatform(c),
		ProductKey: productKey, IdempotencyKey: "date-" + requestID, ReferenceType: "companion_experience",
		Metadata: map[string]any{"scheduled_at": start, "date_request_id": requestID},
	})
	if err != nil {
		if errors.Is(err, credits.ErrInsufficientCredit) {
			_, _ = db.Get().ExecContext(ctx, `UPDATE companion_date_requests SET status='payment_required',
				reason='insufficient_credits',updated_at=CURRENT_TIMESTAMP WHERE id=$1`, requestID)
		} else {
			failDateRequest(requestID)
		}
		writeSpendError(c, err)
		return
	}
	result, eventID, err := fulfillVirtualDate(ctx, userID, companionID, product, start, reaction)
	if err != nil {
		settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if refundErr := credits.Refund(settlementCtx, db.Get(), reservation.ID, err.Error()); refundErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "date failed and refund could not be confirmed", "code": "refund_unconfirmed"})
			return
		}
		failDateRequest(requestID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save accepted date", "code": "date_fulfillment_failed"})
		return
	}
	result["status"] = "accepted"
	result["date_request_id"] = requestID
	result["spend_id"] = reservation.ID
	result["product_key"] = product.Key
	result["coins"] = product.Coins
	settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := credits.Complete(settlementCtx, db.Get(), reservation.ID, eventID, result); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "date accepted but settlement is pending", "code": "settlement_pending"})
		return
	}
	if _, err := db.Get().ExecContext(settlementCtx, `UPDATE companion_date_requests SET status='accepted',
		event_id=$2,result=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, requestID, eventID, jsonValue(result)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "date accepted but response could not be recorded", "code": "settlement_pending"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"balance": reservation.Balance, "product": product, "result": result})
}

func requestedDateTime(input map[string]any) (time.Time, error) {
	value, ok := input["scheduled_at"].(string)
	if !ok {
		return time.Time{}, errInvalidAppointment
	}
	start, err := time.Parse(time.RFC3339, value)
	if err != nil || start.Before(time.Now().Add(5*time.Minute)) || start.After(time.Now().Add(30*24*time.Hour)) {
		return time.Time{}, errInvalidAppointment
	}
	return start.UTC(), nil
}

func failDateRequest(requestID string) {
	_, _ = db.Get().Exec(`UPDATE companion_date_requests SET status='failed',updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND status='requested'`, requestID)
}

func jsonValue(value any) []byte {
	encoded, _ := json.Marshal(value)
	return encoded
}

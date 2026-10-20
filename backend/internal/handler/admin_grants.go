package handler

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

type adminGrantCoinsRequest struct {
	Coins int    `json:"coins" binding:"required,min=1,max=10000000"`
	Note  string `json:"note"`
}

type adminGrantSubscriptionRequest struct {
	PlanID string    `json:"plan_id" binding:"required"`
	EndsAt time.Time `json:"ends_at" binding:"required"`
	Note   string    `json:"note"`
}

type adminGrantOperation struct {
	ID             string     `json:"id"`
	OperatorID     *string    `json:"operator_user_id"`
	OperatorEmail  string     `json:"operator_email"`
	TargetUserID   string     `json:"target_user_id"`
	TargetEmail    string     `json:"target_email"`
	OperationType  string     `json:"operation_type"`
	Coins          int        `json:"coins"`
	PlanID         *string    `json:"plan_id"`
	PlanName       string     `json:"plan_name"`
	SubscriptionID *string    `json:"subscription_id"`
	ExpiresAt      *time.Time `json:"expires_at"`
	Note           string     `json:"note"`
	Platform       string     `json:"platform"`
	Environment    string     `json:"environment"`
	CreatedAt      time.Time  `json:"created_at"`
}

func adminGrantParties(c *gin.Context) (operatorID, operatorEmail, targetID, targetEmail, environment string, ok bool) {
	operatorID = c.GetString("user_id")
	targetID = c.Param("id")
	if err := db.Get().QueryRow(`SELECT email FROM users WHERE id=$1`, operatorID).Scan(&operatorEmail); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "admin operator not found"})
		return "", "", "", "", "", false
	}
	if err := db.Get().QueryRow(`SELECT email,environment FROM users WHERE id=$1`, targetID).Scan(&targetEmail, &environment); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return "", "", "", "", "", false
	}
	return operatorID, operatorEmail, targetID, targetEmail, environment, true
}

func AdminGrantCoins(c *gin.Context) {
	var input adminGrantCoinsRequest
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Note = strings.TrimSpace(input.Note)
	if len(input.Note) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "note must be at most 500 characters"})
		return
	}
	operatorID, operatorEmail, targetID, targetEmail, environment, ok := adminGrantParties(c)
	if !ok {
		return
	}

	tx, err := db.Get().Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start grant"})
		return
	}
	defer tx.Rollback()
	var balance int
	if err := tx.QueryRow(`UPDATE users SET credits_balance=credits_balance+$1,updated_at=CURRENT_TIMESTAMP
		WHERE id=$2 RETURNING credits_balance`, input.Coins, targetID).Scan(&balance); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to grant coins"})
		return
	}
	operationID := uuid.New().String()
	description := "admin grant"
	if input.Note != "" {
		description += ": " + input.Note
	}
	if _, err := tx.Exec(`INSERT INTO credit_transactions
		(id,user_id,amount,balance_after,kind,description,platform,environment)
		VALUES($1,$2,$3,$4,'admin_grant',$5,'system',$6)`, uuid.New().String(), targetID,
		input.Coins, balance, description, environment); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record coin grant"})
		return
	}
	if _, err := tx.Exec(`INSERT INTO admin_grant_operations
		(id,operator_user_id,operator_email,target_user_id,target_email,operation_type,coins,note,platform,environment)
		VALUES($1,$2,$3,$4,$5,'coins',$6,$7,'system',$8)`, operationID, operatorID, operatorEmail,
		targetID, targetEmail, input.Coins, input.Note, environment); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record admin operation"})
		return
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to commit coin grant"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": operationID, "coins": input.Coins, "balance": balance})
}

func AdminGrantSubscription(c *gin.Context) {
	var input adminGrantSubscriptionRequest
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	input.Note = strings.TrimSpace(input.Note)
	if len(input.Note) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "note must be at most 500 characters"})
		return
	}
	if !input.EndsAt.After(time.Now()) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "subscription end date must be in the future"})
		return
	}
	operatorID, operatorEmail, targetID, targetEmail, environment, ok := adminGrantParties(c)
	if !ok {
		return
	}
	var planID, planKey, planName, planPlatform, planEnvironment, productID string
	var coins int
	err := db.Get().QueryRow(`SELECT id,key,name,platform,environment,product_id,coins_granted
		FROM subscription_plans WHERE id=$1 AND enabled=true`, input.PlanID).
		Scan(&planID, &planKey, &planName, &planPlatform, &planEnvironment, &productID, &coins)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "subscription plan not found or disabled"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load subscription plan"})
		return
	}
	if planEnvironment != environment {
		c.JSON(http.StatusBadRequest, gin.H{"error": "subscription plan environment must match the user environment"})
		return
	}
	if productID == "" {
		productID = planKey
	}

	now := time.Now().UTC()
	operationID := uuid.New().String()
	subscriptionID := uuid.New().String()
	tx, err := db.Get().Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start subscription grant"})
		return
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`INSERT INTO subscriptions
		(id,user_id,provider,provider_ref,product_id,entitlement,status,platform,environment,
		 current_period_start,current_period_end,will_renew)
		VALUES($1,$2,'admin',$3,$4,$5,'active',$6,$7,$8,$9,false)`, subscriptionID, targetID,
		operationID, productID, planKey, planPlatform, environment, now, input.EndsAt.UTC()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to grant subscription"})
		return
	}
	var balance int
	if err := tx.QueryRow(`UPDATE users SET credits_balance=credits_balance+$1,updated_at=CURRENT_TIMESTAMP
		WHERE id=$2 RETURNING credits_balance`, coins, targetID).Scan(&balance); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to grant plan coins"})
		return
	}
	if coins > 0 {
		description := "admin subscription grant: " + planName
		if input.Note != "" {
			description += ": " + input.Note
		}
		if _, err := tx.Exec(`INSERT INTO credit_transactions
			(id,user_id,amount,balance_after,kind,description,platform,environment)
			VALUES($1,$2,$3,$4,'admin_subscription_grant',$5,$6,$7)`, uuid.New().String(), targetID,
			coins, balance, description, planPlatform, environment); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record plan coins"})
			return
		}
	}
	if _, err := tx.Exec(`INSERT INTO admin_grant_operations
		(id,operator_user_id,operator_email,target_user_id,target_email,operation_type,coins,plan_id,plan_name,
		 subscription_id,expires_at,note,platform,environment)
		VALUES($1,$2,$3,$4,$5,'subscription',$6,$7,$8,$9,$10,$11,$12,$13)`, operationID, operatorID,
		operatorEmail, targetID, targetEmail, coins, planID, planName, subscriptionID, input.EndsAt.UTC(),
		input.Note, planPlatform, environment); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record admin operation"})
		return
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to commit subscription grant"})
		return
	}
	_ = syncUserCompanionEntitlement(targetID, true)
	c.JSON(http.StatusCreated, gin.H{"id": operationID, "subscription_id": subscriptionID,
		"plan_name": planName, "coins": coins, "balance": balance, "expires_at": input.EndsAt.UTC()})
}

func AdminListGrantOperations(c *gin.Context) {
	targetID := c.Param("id")
	if _, err := adminUserByID(targetID); errors.Is(err, errUserNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		return
	}
	rows, err := db.Get().Query(`SELECT id,operator_user_id,operator_email,target_user_id,target_email,
		operation_type,coins,plan_id,plan_name,subscription_id,expires_at,note,platform,environment,created_at
		FROM admin_grant_operations WHERE target_user_id=$1 ORDER BY created_at DESC,id DESC`, targetID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load grant operations"})
		return
	}
	defer rows.Close()
	items := []adminGrantOperation{}
	for rows.Next() {
		var item adminGrantOperation
		var operatorID, planID, subscriptionID sql.NullString
		var expiresAt sql.NullTime
		if err := rows.Scan(&item.ID, &operatorID, &item.OperatorEmail, &item.TargetUserID, &item.TargetEmail,
			&item.OperationType, &item.Coins, &planID, &item.PlanName, &subscriptionID, &expiresAt,
			&item.Note, &item.Platform, &item.Environment, &item.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan grant operations"})
			return
		}
		item.OperatorID = nullString(operatorID)
		item.PlanID = nullString(planID)
		item.SubscriptionID = nullString(subscriptionID)
		if expiresAt.Valid {
			item.ExpiresAt = &expiresAt.Time
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load grant operations"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

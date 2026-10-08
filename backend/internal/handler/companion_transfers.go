package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

type companionTransferRequest struct {
	Coins      int    `json:"coins" binding:"required"`
	RequestKey string `json:"request_key" binding:"required"`
}

// TransferToCompanion consumes virtual credits, records the gesture, and saves
// the companion's response in one transaction. No user-to-user balance changes.
func TransferToCompanion(c *gin.Context) {
	ctx := c.Request.Context()
	userID, companionID := c.GetString("user_id"), c.Param("id")
	var input companionTransferRequest
	if c.ShouldBindJSON(&input) != nil ||
		(input.Coins != 10 && input.Coins != 30 && input.Coins != 100) ||
		strings.TrimSpace(input.RequestKey) == "" || len(input.RequestKey) > 128 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "choose 10, 30, or 100 coins and provide a request key"})
		return
	}
	input.RequestKey = strings.TrimSpace(input.RequestKey)
	if !requireExperienceAccess(c, userID, companionID) {
		return
	}
	var priorCompanion, priorMessageID string
	var priorCoins int
	err := db.Get().QueryRowContext(ctx, `SELECT companion_id,coins,COALESCE(message_id,'')
		FROM companion_transfers WHERE user_id=$1 AND request_key=$2`, userID, input.RequestKey).
		Scan(&priorCompanion, &priorCoins, &priorMessageID)
	if err == nil {
		if priorCompanion != companionID || priorCoins != input.Coins {
			c.JSON(http.StatusConflict, gin.H{"error": "request key already used for another transfer"})
			return
		}
		var balance int
		_ = db.Get().QueryRowContext(ctx, `SELECT credits_balance FROM users WHERE id=$1`, userID).Scan(&balance)
		var companionBalance int
		_ = db.Get().QueryRowContext(ctx, `SELECT gifted_coins_balance FROM companions WHERE id=$1 AND user_id=$2`, companionID, userID).Scan(&companionBalance)
		c.JSON(http.StatusOK, gin.H{"balance": balance, "companion_balance": companionBalance,
			"message_id": priorMessageID, "idempotent": true})
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check transfer"})
		return
	}
	var available int
	if err := db.Get().QueryRowContext(ctx, `SELECT credits_balance FROM users WHERE id=$1`, userID).Scan(&available); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check balance"})
		return
	}
	if available < input.Coins {
		c.JSON(http.StatusPaymentRequired, gin.H{"error": "insufficient credits", "code": "insufficient_credits", "action": "open_credits"})
		return
	}
	if companionAgent == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "agent service is unavailable"})
		return
	}
	conversationID, err := experienceConversation(ctx, userID, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to open conversation"})
		return
	}
	replyCtx, cancel := context.WithTimeout(ctx, 50*time.Second)
	defer cancel()
	reply, err := companionAgent.ComposeTransferReply(replyCtx, conversationID, userID, input.Coins)
	if err != nil || strings.TrimSpace(reply) == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "companion could not respond to transfer"})
		return
	}
	transferID, userMessageID, replyID := uuid.New().String(), uuid.New().String(), uuid.New().String()
	payload, _ := json.Marshal(map[string]any{"coins": input.Coins, "transfer_id": transferID})
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to begin transfer"})
		return
	}
	defer tx.Rollback()
	claim, err := tx.ExecContext(ctx, `INSERT INTO companion_transfers(id,user_id,companion_id,request_key,coins,message_id)
		VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(user_id,request_key) DO NOTHING`,
		transferID, userID, companionID, input.RequestKey, input.Coins, userMessageID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save transfer"})
		return
	}
	claimed, _ := claim.RowsAffected()
	if claimed == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "transfer was already submitted; refresh balance", "code": "transfer_duplicate"})
		return
	}
	var balance int
	err = tx.QueryRowContext(ctx, `UPDATE users SET credits_balance=credits_balance-$1,updated_at=CURRENT_TIMESTAMP
		WHERE id=$2 AND credits_balance>=$1 RETURNING credits_balance`, input.Coins, userID).Scan(&balance)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusPaymentRequired, gin.H{"error": "insufficient credits", "code": "insufficient_credits", "action": "open_credits"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to debit credits"})
		return
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO credit_transactions(id,user_id,amount,balance_after,kind,description,platform,environment)
		VALUES($1,$2,$3,$4,'consume',$5,$6,$7)`, uuid.New().String(), userID, -input.Coins,
		balance, "companion-transfer:"+transferID, requestPlatform(c), currentEnvironment())
	if err == nil {
		_, err = tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,delivery_status)
			VALUES($1,$2,'user','transfer',$3,$4,'companion_transfer','delivered')`, userMessageID,
			conversationID, strconv.Itoa(input.Coins)+" 🪙", payload)
	}
	if err == nil {
		_, err = tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,delivery_status)
			VALUES($1,$2,'assistant','text',$3,'{}'::jsonb,'transfer_reply','delivered')`, replyID, conversationID, reply)
	}
	var companionBalance int
	if err == nil {
		err = tx.QueryRowContext(ctx, `UPDATE companions SET gifted_coins_balance=gifted_coins_balance+$1,
			updated_at=CURRENT_TIMESTAMP WHERE id=$2 AND user_id=$3
			RETURNING gifted_coins_balance`, input.Coins, companionID, userID).Scan(&companionBalance)
	}
	if err == nil {
		metadata, _ := json.Marshal(map[string]any{"transfer_id": transferID, "coins": input.Coins})
		_, err = tx.ExecContext(ctx, `INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata)
			VALUES($1,$2,'kind_gesture',$3,50,CURRENT_TIMESTAMP,$4)`, uuid.New().String(), companionID,
			"The user sent "+strconv.Itoa(input.Coins)+" virtual coins. You responded: "+reply, string(metadata))
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record transfer"})
		return
	}
	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to finish transfer"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"balance": balance, "companion_balance": companionBalance,
		"transfer_id": transferID, "message_id": userMessageID, "reply_id": replyID})
}

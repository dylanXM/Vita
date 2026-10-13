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
	"vita/internal/agent"
	"vita/internal/credits"
	"vita/internal/db"
)

func purchaseMediaExperience(c *gin.Context, userID, companionID, key string, input experienceRequest) {
	ctx := c.Request.Context()
	params := credits.ReserveParams{UserID: userID, CompanionID: companionID, Environment: currentEnvironment(), Platform: requestPlatform(c), ProductKey: key, IdempotencyKey: input.IdempotencyKey, ReferenceType: "companion_experience", Metadata: input.Input}
	reservation, err := credits.Reserve(ctx, db.Get(), params)
	if err != nil {
		writeSpendError(c, err)
		return
	}
	if reservation.Idempotent {
		c.JSON(200, gin.H{"balance": reservation.Balance, "product": reservation.Product, "result": reservation.Result, "idempotent": true})
		return
	}
	product := reservation.Product
	var errGeneration error
	if companionAgent == nil {
		errGeneration = fmt.Errorf("media service is unavailable")
	}
	var message *agent.SavedMessage
	outfitKey := ""
	if errGeneration == nil {
		switch product.Category {
		case "photo":
			message, err = companionAgent.PrepareRequestedLifePhoto(ctx, userID, companionID)
		case "voice":
			message, err = companionAgent.PrepareLatestReplySpeech(ctx, userID, companionID)
		case "outfit":
			outfitKey = key
			style, _ := product.Metadata["style"].(string)
			message, err = companionAgent.GenerateOutfitPhoto(ctx, userID, companionID, key, style)
		default:
			err = fmt.Errorf("unsupported media product")
		}
	}
	if errGeneration != nil {
		err = errGeneration
	}
	if err == nil && (message == nil || strings.TrimSpace(message.MediaURL) == "") {
		err = fmt.Errorf("media generation returned no usable result")
	}
	if err != nil {
		refundMediaFailure(c, reservation.ID, err)
		return
	}
	// A disconnected client must not prevent completion after successful generation.
	settlement, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	reservation, err = settleMediaExperience(settlement, db.Get(), params, reservation, message, outfitKey)
	if err != nil {
		refundMediaFailure(c, reservation.ID, err)
		return
	}
	c.JSON(200, gin.H{"balance": reservation.Balance, "product": reservation.Product, "result": reservation.Result, "idempotent": reservation.Idempotent})
}

func settleMediaExperience(ctx context.Context, database *sql.DB, params credits.ReserveParams, reservation *credits.Reservation, message *agent.SavedMessage, outfitKey string) (*credits.Reservation, error) {
	tx, err := database.BeginTx(ctx, nil)
	if err != nil {
		return reservation, err
	}
	defer tx.Rollback()
	var status string
	if err := tx.QueryRowContext(ctx, `SELECT status FROM credit_spends WHERE id=$1 FOR UPDATE`, reservation.ID).Scan(&status); err != nil {
		return reservation, err
	}
	if status != "reserved" {
		return reservation, fmt.Errorf("media spend is no longer reserved")
	}
	// A concurrent purchase must not grant the same outfit twice.
	if err = agent.DeliverPreparedMedia(ctx, tx, params.UserID, params.CompanionID, outfitKey, message); err != nil {
		return reservation, err
	}
	result := map[string]any{"message": message, "spend_id": reservation.ID, "product_key": reservation.Product.Key, "coins": reservation.Product.Coins}
	if outfitKey != "" {
		result["equipped"] = true
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		return reservation, err
	}
	if _, err = tx.ExecContext(ctx, `UPDATE credit_spends SET status='completed',reference_id=$2,result=$3,completed_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND status='reserved'`, reservation.ID, message.ID, encoded); err != nil {
		return reservation, err
	}
	if err = tx.Commit(); err != nil {
		return reservation, err
	}
	reservation.Result = result
	reservation.Status = "completed"
	return reservation, nil
}

func refundMediaFailure(c *gin.Context, spendID string, failure error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	// Resolve a commit whose acknowledgment failed before attempting a refund.
	var status string
	if err := db.Get().QueryRowContext(ctx, `SELECT status FROM credit_spends WHERE id=$1`, spendID).Scan(&status); err == nil && status == "completed" {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "media delivered; retry the same request to retrieve the result", "code": "settlement_pending"})
		return
	}
	if err := credits.Refund(ctx, db.Get(), spendID, failure.Error()); err != nil {
		c.JSON(500, gin.H{"error": "media failed and refund could not be confirmed", "code": "refund_unconfirmed"})
		return
	}
	c.JSON(http.StatusUnprocessableEntity, gin.H{"error": failure.Error(), "code": "experience_failed", "refunded": true})
}

// Existing outfits reuse their delivered photo; old outfits with no media are
// repaired without charging a second time.
func equipOwnedMediaOutfit(c *gin.Context, userID, companionID, key string) {
	ctx := c.Request.Context()
	var raw string
	err := db.Get().QueryRowContext(ctx, `SELECT to_jsonb(m)::text FROM messages m JOIN conversations cv ON cv.id=m.conversation_id WHERE cv.user_id=$1 AND cv.companion_id=$2 AND m.source='paid_outfit' AND m.payload->>'product_key'=$3 AND m.payload->>'portrait_reference'=(SELECT COALESCE(NULLIF(c.avatar_url,''),p.image_url,'') FROM companions c LEFT JOIN companion_portraits p ON p.id=c.portrait_id WHERE c.id=$2 AND c.user_id=$1) AND COALESCE(m.media_url,'')<>'' ORDER BY m.created_at DESC LIMIT 1`, userID, companionID, key).Scan(&raw)
	var message *agent.SavedMessage
	if err == nil {
		message = &agent.SavedMessage{}
		err = json.Unmarshal([]byte(raw), message)
	} else if err == sql.ErrNoRows {
		var style string
		err = db.Get().QueryRowContext(ctx, `SELECT COALESCE(metadata->>'style','') FROM credit_products WHERE environment=$1 AND product_key=$2`, currentEnvironment(), key).Scan(&style)
		if err == nil && companionAgent != nil {
			message, err = companionAgent.GenerateOutfitPhoto(ctx, userID, companionID, key, style)
		} else if err == nil {
			err = fmt.Errorf("media service is unavailable")
		}
		if err == nil {
			tx, e := db.Get().BeginTx(ctx, nil)
			if e != nil {
				err = e
			} else {
				err = agent.DeliverPreparedMedia(ctx, tx, userID, companionID, "", message)
				if err == nil {
					err = tx.Commit()
				}
				tx.Rollback()
			}
		}
	}
	if err != nil {
		c.JSON(422, gin.H{"error": err.Error(), "code": "experience_failed", "charged": false})
		return
	}
	if _, err = db.Get().ExecContext(ctx, `UPDATE companions SET equipped_outfit_key=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2`, companionID, userID, key); err != nil {
		c.JSON(500, gin.H{"error": "failed to equip outfit"})
		return
	}
	var balance int
	if err = db.Get().QueryRowContext(ctx, `SELECT credits_balance FROM users WHERE id=$1`, userID).Scan(&balance); err != nil {
		c.JSON(500, gin.H{"error": "failed to load balance"})
		return
	}
	c.JSON(200, gin.H{"balance": balance, "product_key": key, "equipped": true, "already_owned": true, "result": gin.H{"message": message, "equipped": true, "coins": 0, "product_key": key}})
}

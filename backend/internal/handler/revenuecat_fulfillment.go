package handler

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"vita/internal/db"
)

func RevenueCatWebhook(c *gin.Context) {
	if billingCfg.RevenueCatWebhookSecret == "" {
		c.JSON(503, gin.H{"error": "revenuecat webhook is not configured"})
		return
	}
	auth := []byte(c.GetHeader("Authorization"))
	valid := hmac.Equal(auth, []byte(billingCfg.RevenueCatWebhookSecret)) || hmac.Equal(auth, []byte("Bearer "+billingCfg.RevenueCatWebhookSecret))
	if !valid {
		c.JSON(401, gin.H{"error": "invalid webhook secret"})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 1<<20)
	var payload revenueCatWebhookPayload
	if c.ShouldBindJSON(&payload) != nil || payload.Event == nil || payload.Event.Type == "" {
		c.JSON(400, gin.H{"error": "invalid event"})
		return
	}
	raw, err := json.Marshal(payload.Event)
	if err != nil {
		c.JSON(400, gin.H{"error": "invalid event"})
		return
	}
	id := payload.Event.ID
	if id == "" {
		digest := sha256.Sum256(raw)
		id = "payload:" + hex.EncodeToString(digest[:])
	}
	// A 2xx means the event is durably saved, never that uncommitted grants worked.
	if _, err := db.Get().ExecContext(c.Request.Context(), `INSERT INTO revenuecat_webhook_events(id,payload) VALUES($1,$2) ON CONFLICT DO NOTHING`, id, raw); err != nil {
		c.JSON(503, gin.H{"error": "failed to persist purchase event"})
		return
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(c.Request.Context()), 10*time.Second)
	defer cancel()
	if err := processRevenueCatJob(ctx, id); err != nil {
		log.Printf("RevenueCat fulfillment pending event=%s: %v", id, err)
	}
	c.JSON(http.StatusOK, gin.H{"received": true})
}

func RunRevenueCatFulfillment(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		if err := ProcessRevenueCatWebhookJobs(ctx); err != nil {
			log.Printf("RevenueCat fulfillment worker: %v", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func ProcessRevenueCatWebhookJobs(ctx context.Context) error {
	rows, err := db.Get().QueryContext(ctx, `SELECT id FROM revenuecat_webhook_events WHERE status='pending' AND retry_at<=CURRENT_TIMESTAMP
 AND (claimed_at IS NULL OR claimed_at<CURRENT_TIMESTAMP-INTERVAL '1 minute') ORDER BY created_at,id LIMIT 20`)
	if err != nil {
		return err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := processRevenueCatJob(ctx, id); err != nil {
			log.Printf("RevenueCat event %s retry: %v", id, err)
		}
	}
	return nil
}

func processRevenueCatJob(ctx context.Context, id string) error {
	var raw string
	err := db.Get().QueryRowContext(ctx, `UPDATE revenuecat_webhook_events SET claimed_at=CURRENT_TIMESTAMP,attempts=attempts+1
 WHERE id=$1 AND status='pending' AND retry_at<=CURRENT_TIMESTAMP
 AND (claimed_at IS NULL OR claimed_at<CURRENT_TIMESTAMP-INTERVAL '1 minute') RETURNING payload::text`, id).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	var ev revenueCatEvent
	if err = json.Unmarshal([]byte(raw), &ev); err == nil {
		jobCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
		err = fulfillRevenueCatEvent(jobCtx, id, &ev)
		cancel()
	}
	if err != nil {
		cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
		defer cancel()
		_, saveErr := db.Get().ExecContext(cleanup, `UPDATE revenuecat_webhook_events SET claimed_at=NULL,last_error=$2,
  retry_at=CURRENT_TIMESTAMP+INTERVAL '10 seconds'*LEAST(180,attempts*attempts) WHERE id=$1 AND status='pending'`, id, err.Error())
		if saveErr != nil {
			return fmt.Errorf("%v; failed to save retry: %w", err, saveErr)
		}
	}
	return err
}

func resolveRevenueCatUser(tx *sql.Tx, ev *revenueCatEvent) (string, error) {
	var found string
	err := tx.QueryRow(`SELECT id FROM users WHERE id=$1`, ev.AppUserID).Scan(&found)
	if err == nil {
		return found, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}
	for _, alias := range ev.Aliases {
		var id string
		err := tx.QueryRow(`SELECT id FROM users WHERE id=$1`, alias).Scan(&id)
		if errors.Is(err, sql.ErrNoRows) {
			continue
		}
		if err != nil {
			return "", err
		}
		if found != "" && found != id {
			return "", fmt.Errorf("multiple Vita users match RevenueCat aliases")
		}
		found = id
	}
	if found == "" {
		return "", fmt.Errorf("RevenueCat customer is not linked to a Vita user")
	}
	return found, nil
}

func fulfillRevenueCatEvent(ctx context.Context, eventID string, ev *revenueCatEvent) error {
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var state string
	if err := tx.QueryRowContext(ctx, `SELECT status FROM revenuecat_webhook_events WHERE id=$1 FOR UPDATE`, eventID).Scan(&state); err != nil {
		return err
	}
	if state == "completed" {
		return nil
	}
	var affected []string
	switch ev.Type {
	case "INITIAL_PURCHASE", "NON_RENEWING_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE", "CANCELLATION", "EXPIRATION", "SUBSCRIPTION_PAUSED":
		if err := applyRevenueCatPurchase(tx, ev); err != nil {
			return err
		}
		owner, err := resolveRevenueCatUser(tx, ev)
		if err != nil {
			return err
		}
		affected = append(affected, owner)
	case "TRANSFER":
		// RevenueCat's transfer payload uses arrays, not the old app_user_id columns.
		to := ev.TransferredTo
		if len(to) == 0 && ev.NewAppUserID != "" {
			to = []string{ev.NewAppUserID}
		}
		owner, err := resolveRevenueCatUser(tx, &revenueCatEvent{AppUserID: firstString(to), Aliases: to})
		if err != nil {
			return err
		}
		from := ev.TransferredFrom
		if len(from) == 0 && ev.AppUserID != "" {
			from = []string{ev.AppUserID}
		}
		affected = append(affected, owner)
		for _, old := range from {
			affected = append(affected, old)
			if _, err := tx.Exec(`UPDATE subscriptions SET user_id=$1,updated_at=CURRENT_TIMESTAMP WHERE provider='revenuecat' AND user_id=$2`, owner, old); err != nil {
				return err
			}
		}
	default:
		// TEST and informational events have no fulfillment side effects.
	}
	if _, err := tx.ExecContext(ctx, `UPDATE revenuecat_webhook_events SET status='completed',claimed_at=NULL,last_error='' WHERE id=$1`, eventID); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	for _, userID := range affected {
		if active, err := userHasActiveSubscription(userID); err == nil {
			if err := syncUserCompanionEntitlement(userID, active); err != nil {
				log.Printf("RevenueCat companion access refresh: %v", err)
			}
		}
	}
	return nil
}

func firstString(values []string) string {
	if len(values) > 0 {
		return values[0]
	}
	return ""
}

func applyRevenueCatPurchase(tx *sql.Tx, ev *revenueCatEvent) error {
	userID, err := resolveRevenueCatUser(tx, ev)
	if err != nil {
		return err
	}
	platform := platformFromRevenueCatStore(ev.Store)
	catalogPlatform := billingCatalogPlatform(platform)
	var kind string
	var coins int
	rows, err := tx.Query(`SELECT 'coin_pack',coins FROM coin_packs WHERE environment=$1 AND platform=$2 AND product_id=$3
 UNION ALL SELECT 'subscription',coins_granted FROM subscription_plans WHERE environment=$1 AND platform=$2 AND product_id=$3`, currentEnvironment(), catalogPlatform, ev.ProductID)
	if err != nil {
		return err
	}
	count := 0
	for rows.Next() {
		if err := rows.Scan(&kind, &coins); err != nil {
			rows.Close()
			return err
		}
		count++
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	if count > 1 {
		return fmt.Errorf("ambiguous billing product %s", ev.ProductID)
	}
	if count == 0 {
		coins = creditsFromProductID(ev.ProductID)
		if coins > 0 {
			kind = "coin_pack"
		} else {
			return fmt.Errorf("billing product %s is not configured in the %s catalog", ev.ProductID, catalogPlatform)
		}
	}
	purchasedAt := time.UnixMilli(ev.PurchasedAtMS).UTC()
	transactionID := ev.TransactionID
	if transactionID == "" && ev.OriginalTransactionID != "" && ev.PurchasedAtMS > 0 {
		transactionID = fmt.Sprintf("%s:%d", ev.OriginalTransactionID, ev.PurchasedAtMS)
	}
	isPurchase := ev.Type == "INITIAL_PURCHASE" || ev.Type == "RENEWAL" || ev.Type == "NON_RENEWING_PURCHASE"
	if isPurchase && (transactionID == "" || ev.PurchasedAtMS <= 0) {
		return fmt.Errorf("purchase has no transaction identifier or date")
	}
	if kind == "coin_pack" {
		if ev.Type == "INITIAL_PURCHASE" || ev.Type == "NON_RENEWING_PURCHASE" {
			if coins > 0 {
				if _, err := grantCreditsInTx(tx, userID, coins, "purchase", revenueCatGrantKey("rc-purchase", ev), platform, true); err != nil {
					return err
				}
			}
		} else {
			return nil
		}
	} else {
		if ev.OriginalTransactionID == "" {
			return fmt.Errorf("subscription has no original transaction identifier")
		}
		ids := make([]string, 0, len(ev.EntitlementIDs))
		seen := map[string]bool{}
		for _, id := range append(ev.EntitlementIDs, ev.EntitlementID) {
			id = strings.TrimSpace(id)
			if id != "" && !seen[id] {
				ids = append(ids, id)
				seen[id] = true
			}
		}
		encoded, _ := json.Marshal(ids)
		status, willRenew := "active", ev.Type != "NON_RENEWING_PURCHASE"
		if ev.Type == "CANCELLATION" {
			willRenew = false
		}
		if ev.Type == "EXPIRATION" {
			status = "expired"
			willRenew = false
		}
		// A pause is scheduled; the paid period remains active until expiration.
		if ev.Type == "SUBSCRIPTION_PAUSED" {
			willRenew = false
		}
		var start, end any
		if ev.PurchasedAtMS > 0 {
			start = purchasedAt
		}
		if ev.ExpirationAtMS > 0 {
			end = time.UnixMilli(ev.ExpirationAtMS).UTC()
		}
		eventAt := ev.EventTimestampMS
		if eventAt == 0 {
			eventAt = ev.PurchasedAtMS
		}
		_, err := tx.Exec(`INSERT INTO subscriptions(id,user_id,provider,provider_ref,product_id,entitlement,entitlement_ids,status,platform,environment,current_period_start,current_period_end,will_renew,revenuecat_event_at_ms)
  VALUES($1,$2,'revenuecat',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
  ON CONFLICT(provider,provider_ref) DO UPDATE SET user_id=$2,product_id=$4,entitlement=$5,entitlement_ids=$6,status=$7,platform=$8,
  current_period_start=COALESCE($10,subscriptions.current_period_start),current_period_end=COALESCE($11,subscriptions.current_period_end),will_renew=$12,revenuecat_event_at_ms=$13,updated_at=CURRENT_TIMESTAMP
  WHERE subscriptions.revenuecat_event_at_ms<=$13`, uuid.New().String(), userID, ev.OriginalTransactionID, ev.ProductID, firstString(ids), string(encoded), status, platform, currentEnvironment(), start, end, willRenew, eventAt)
		if err != nil {
			return err
		}
		// Only a paid initial purchase or renewal creates an allowance, never a
		// product-change/uncancellation notification for the same paid period.
		if (ev.Type == "INITIAL_PURCHASE" || ev.Type == "RENEWAL" || ev.Type == "NON_RENEWING_PURCHASE") && ev.PeriodType != "TRIAL" && coins > 0 {
			if _, err := grantCreditsInTx(tx, userID, coins, "grant", revenueCatGrantKey("rc-subscription", ev), platform, true); err != nil {
				return err
			}
		}
	}
	if isPurchase {
		delivered := coins
		if kind == "subscription" && ev.PeriodType == "TRIAL" {
			delivered = 0
		}
		recorded, recordErr := tx.Exec(`INSERT INTO billing_purchases(id,user_id,transaction_id,store_transaction_id,kind,provider,platform,environment,product_id,currency,credits,status,purchased_at,fulfilled_at)
  VALUES($1,$2,$3,$4,$5,'revenuecat',$6,$7,$8,'',$9,'paid',$10,CURRENT_TIMESTAMP)
  ON CONFLICT(provider,transaction_id) DO UPDATE SET store_transaction_id=EXCLUDED.store_transaction_id,fulfilled_at=CURRENT_TIMESTAMP WHERE billing_purchases.user_id=EXCLUDED.user_id`, uuid.New().String(), userID, revenueCatPurchaseKey(ev), ev.TransactionID, kind, platform, currentEnvironment(), ev.ProductID, delivered, purchasedAt)
		if recordErr != nil {
			return recordErr
		}
		count, err := recorded.RowsAffected()
		if err != nil {
			return err
		}
		if count != 1 {
			return fmt.Errorf("purchase transaction is already owned by another user")
		}
	}
	return nil
}

func revenueCatPurchaseKey(ev *revenueCatEvent) string {
	if ev.OriginalTransactionID != "" && ev.PurchasedAtMS > 0 {
		return fmt.Sprintf("%s:%d", ev.OriginalTransactionID, ev.PurchasedAtMS)
	}
	return ev.TransactionID
}
func revenueCatGrantKey(prefix string, ev *revenueCatEvent) string {
	return prefix + ":" + revenueCatPurchaseKey(ev)
}

// This endpoint only reads server-fulfilled orders; client data can never mint coins.
func ConfirmBillingPurchase(c *gin.Context) {
	var input struct {
		ProductID     string `json:"product_id"`
		TransactionID string `json:"transaction_id"`
		PurchasedAt   string `json:"purchased_at"`
	}
	if c.ShouldBindJSON(&input) != nil || input.ProductID == "" || len(input.ProductID) > 300 || len(input.TransactionID) > 300 {
		c.JSON(400, gin.H{"error": "invalid purchase reference"})
		return
	}
	at, err := time.Parse(time.RFC3339Nano, input.PurchasedAt)
	if err != nil {
		c.JSON(400, gin.H{"error": "invalid purchase date"})
		return
	}
	var fulfilled bool
	err = db.Get().QueryRowContext(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM billing_purchases WHERE user_id=$1 AND provider='revenuecat' AND product_id=$2 AND status='paid' AND fulfilled_at IS NOT NULL
 AND (($3<>'' AND (store_transaction_id=$3 OR transaction_id=$3)) OR ((store_transaction_id='' OR $3='') AND purchased_at>=$4 AND purchased_at<=$5)))`, c.GetString("user_id"), input.ProductID, input.TransactionID, at.Add(-time.Second), at.Add(time.Second)).Scan(&fulfilled)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to confirm fulfillment"})
		return
	}
	c.JSON(200, gin.H{"fulfilled": fulfilled})
}

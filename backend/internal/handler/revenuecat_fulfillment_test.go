package handler

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"vita/internal/config"
	"vita/internal/db"
)

func TestRevenueCatFulfillmentPostgres(t *testing.T) {
	dsn := os.Getenv("VITA_BILLING_TEST_DSN")
	if dsn == "" {
		t.Skip("requires a dedicated vita_billing_test_ database")
	}
	parsed, err := url.Parse(dsn)
	if err != nil || !strings.HasPrefix(strings.TrimPrefix(parsed.Path, "/"), "vita_billing_test_") {
		t.Fatal("refusing to reset an application database")
	}
	reset, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := reset.Exec(`DROP SCHEMA public CASCADE;CREATE SCHEMA public`); err != nil {
		t.Fatal(err)
	}
	reset.Close()
	database, err := db.Open(&config.Config{DBDSN: dsn, AutoMigrate: true})
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	previous := billingCfg
	t.Cleanup(func() { billingCfg = previous })
	billingCfg = BillingConfig{RevenueCatWebhookSecret: "local-test-secret", SubscriptionCreditsMonthly: 999}
	gin.SetMode(gin.TestMode)
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := database.Exec(q, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`INSERT INTO users(id,email) VALUES('u','coins@example.test'),('sub','subscription@example.test'),('trial','trial@example.test')`)
	exec(`UPDATE coin_packs SET coins=135 WHERE platform='app' AND product_id='vita.coins.100'`)
	exec(`UPDATE subscription_plans SET coins_granted=321 WHERE platform='app' AND product_id='vita.plus.monthly'`)
	deliver := func(ev revenueCatEvent) int {
		payload, _ := json.Marshal(revenueCatWebhookPayload{Event: &ev})
		response := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(response)
		c.Request = httptest.NewRequest(http.MethodPost, "/v1/webhooks/revenuecat", bytes.NewReader(payload))
		c.Request.Header.Set("Authorization", "Bearer local-test-secret")
		RevenueCatWebhook(c)
		return response.Code
	}
	balance := func(user string) int {
		t.Helper()
		var n int
		if err := database.QueryRow(`SELECT credits_balance FROM users WHERE id=$1`, user).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	now := time.Now().UTC().Truncate(time.Millisecond)
	coins := revenueCatEvent{ID: "coins-event", Type: "NON_RENEWING_PURCHASE", AppUserID: "u", ProductID: "vita.coins.100", Store: "TEST_STORE", OriginalTransactionID: "coin-original", TransactionID: "coin-store-id", PurchasedAtMS: now.UnixMilli(), EventTimestampMS: now.UnixMilli()}
	if code := deliver(coins); code != 200 {
		t.Fatalf("webhook status %d", code)
	}
	if got := balance("u"); got != 135 {
		t.Fatalf("test store ignored app catalog: %d", got)
	}
	if code := deliver(coins); code != 200 || balance("u") != 135 {
		t.Fatal("webhook replay duplicated coins")
	}
	// Existing dashboard setups may put the raw shared secret in Authorization.
	raw, _ := json.Marshal(revenueCatWebhookPayload{Event: &coins})
	rawResponse := httptest.NewRecorder()
	rawContext, _ := gin.CreateTestContext(rawResponse)
	rawContext.Request = httptest.NewRequest(http.MethodPost, "/v1/webhooks/revenuecat", bytes.NewReader(raw))
	rawContext.Request.Header.Set("Authorization", "local-test-secret")
	RevenueCatWebhook(rawContext)
	if rawResponse.Code != 200 || balance("u") != 135 {
		t.Fatal("raw Authorization configuration failed or duplicated coins")
	}

	// Concurrent deliveries of the same paid transaction with different event IDs.
	var wg sync.WaitGroup
	codes := make(chan int, 2)
	for _, id := range []string{"duplicate-a", "duplicate-b"} {
		wg.Add(1)
		go func(id string) { defer wg.Done(); copy := coins; copy.ID = id; codes <- deliver(copy) }(id)
	}
	wg.Wait()
	close(codes)
	for code := range codes {
		if code != 200 {
			t.Fatalf("duplicate status %d", code)
		}
	}
	if balance("u") != 135 {
		t.Fatal("concurrent delivery duplicated grant")
	}
	var ledgerCount int
	if err := database.QueryRow(`SELECT COUNT(*) FROM credit_transactions WHERE user_id='u'`).Scan(&ledgerCount); err != nil || ledgerCount != 1 {
		t.Fatalf("ledger count %d %v", ledgerCount, err)
	}

	// A paid transaction cannot be reused to credit another Vita account.
	crossUser := coins
	crossUser.ID = "cross-user-event"
	crossUser.AppUserID = "sub"
	if deliver(crossUser) != 200 || balance("sub") != 0 {
		t.Fatal("transaction ownership allowed a second grant")
	}

	// Any failure after the balance update must roll back coins, grant key and order.
	exec(`CREATE FUNCTION reject_test_order() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.transaction_id LIKE 'rollback:%' THEN RAISE EXCEPTION 'injected order failure'; END IF;RETURN NEW;END $$`)
	exec(`CREATE TRIGGER reject_test_order BEFORE INSERT ON billing_purchases FOR EACH ROW EXECUTE FUNCTION reject_test_order()`)
	failed := coins
	failed.ID = "rollback-event"
	failed.OriginalTransactionID = "rollback"
	failed.TransactionID = "rollback-store"
	failed.PurchasedAtMS = now.Add(time.Second).UnixMilli()
	if deliver(failed) != 200 {
		t.Fatal("durably saved failure should be acknowledged")
	}
	var status string
	if err := database.QueryRow(`SELECT status FROM revenuecat_webhook_events WHERE id='rollback-event'`).Scan(&status); err != nil || status != "pending" {
		t.Fatalf("lost retry: %s %v", status, err)
	}
	if balance("u") != 135 {
		t.Fatal("failed fulfillment left a credit grant")
	}
	exec(`DROP TRIGGER reject_test_order ON billing_purchases;DROP FUNCTION reject_test_order()`)
	exec(`UPDATE revenuecat_webhook_events SET retry_at=CURRENT_TIMESTAMP WHERE id='rollback-event'`)
	if err := ProcessRevenueCatWebhookJobs(t.Context()); err != nil {
		t.Fatal(err)
	}
	if balance("u") != 270 {
		t.Fatal("worker did not recover pending payment")
	}

	subscription := revenueCatEvent{ID: "subscription-event", Type: "INITIAL_PURCHASE", AppUserID: "sub", ProductID: "vita.plus.monthly", Store: "TEST_STORE", OriginalTransactionID: "subscription-original", TransactionID: "subscription-store-id", PurchasedAtMS: now.UnixMilli(), ExpirationAtMS: now.Add(30 * 24 * time.Hour).UnixMilli(), EventTimestampMS: now.UnixMilli(), EntitlementIDs: []string{"plus", "audio"}, PeriodType: "NORMAL"}
	if deliver(subscription) != 200 || balance("sub") != 321 {
		t.Fatal("subscription ignored configured allowance")
	}
	getSubscription := func(user string) map[string]any {
		t.Helper()
		response := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(response)
		c.Set("user_id", user)
		c.Request = httptest.NewRequest("GET", "/v1/me/subscription", nil)
		GetMySubscription(c)
		var data map[string]any
		if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &data) != nil {
			t.Fatalf("subscription response: %s", response.Body)
		}
		return data
	}
	plan := getSubscription("sub")
	if plan["is_subscribed"] != true || len(plan["entitlements"].([]any)) != 2 {
		t.Fatalf("array-only entitlement not active: %+v", plan)
	}
	change := subscription
	change.ID = "product-change"
	change.Type = "PRODUCT_CHANGE"
	change.EventTimestampMS = now.Add(time.Second).UnixMilli()
	if deliver(change) != 200 || balance("sub") != 321 {
		t.Fatal("product change duplicated monthly coins")
	}
	trial := subscription
	trial.ID = "trial-event"
	trial.AppUserID = "trial"
	trial.OriginalTransactionID = "trial-original"
	trial.TransactionID = "trial-store-id"
	trial.PeriodType = "TRIAL"
	if deliver(trial) != 200 || balance("trial") != 0 || getSubscription("trial")["is_subscribed"] != true {
		t.Fatal("trial fulfillment incorrect")
	}
	expired := subscription
	expired.ID = "expiry-event"
	expired.Type = "EXPIRATION"
	expired.EventTimestampMS = now.Add(2 * time.Second).UnixMilli()
	if deliver(expired) != 200 || getSubscription("sub")["is_subscribed"] != false {
		t.Fatal("expiry not applied")
	}
	late := subscription
	late.ID = "late-initial-event"
	if deliver(late) != 200 || getSubscription("sub")["is_subscribed"] != false || balance("sub") != 321 {
		t.Fatal("out-of-order event reactivated subscription or duplicated credits")
	}

	confirm := func(user, product, transaction string, at time.Time) bool {
		t.Helper()
		raw, _ := json.Marshal(map[string]string{"product_id": product, "transaction_id": transaction, "purchased_at": at.Format(time.RFC3339Nano)})
		response := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(response)
		c.Set("user_id", user)
		c.Request = httptest.NewRequest("POST", "/v1/me/billing/confirm", bytes.NewReader(raw))
		ConfirmBillingPurchase(c)
		var data map[string]bool
		if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &data) != nil {
			t.Fatalf("confirmation: %s", response.Body)
		}
		return data["fulfilled"]
	}
	if !confirm("u", coins.ProductID, coins.TransactionID, now) || confirm("sub", coins.ProductID, coins.TransactionID, now) || confirm("u", coins.ProductID, "forged", now) {
		t.Fatal("confirmation does not enforce ownership and exact transaction")
	}

	// Historical paid-without-grant rows must not be reported as delivered.
	historical := coins
	historical.ID = "historical-event"
	historical.OriginalTransactionID = "historical"
	historical.TransactionID = "historical-store"
	historical.PurchasedAtMS = now.Add(3 * time.Second).UnixMilli()
	exec(`INSERT INTO billing_purchases(id,user_id,transaction_id,kind,provider,platform,environment,product_id,credits,status,purchased_at) VALUES('old-paid','u',$1,'coin_pack','revenuecat','app','prod',$2,135,'paid',$3)`, revenueCatPurchaseKey(&historical), historical.ProductID, time.UnixMilli(historical.PurchasedAtMS))
	if confirm("u", historical.ProductID, historical.TransactionID, time.UnixMilli(historical.PurchasedAtMS)) {
		t.Fatal("unfulfilled historical order reported as delivered")
	}
	if deliver(historical) != 200 || balance("u") != 405 || !confirm("u", historical.ProductID, historical.TransactionID, time.UnixMilli(historical.PurchasedAtMS)) {
		t.Fatal("historical event replay did not recover fulfillment")
	}

	// Unknown product keeps a durable retry; repairing the catalog delivers it once.
	unknown := coins
	unknown.ID = "unknown-product-event"
	unknown.ProductID = "custom.coin.pack"
	unknown.OriginalTransactionID = "unknown"
	unknown.TransactionID = "unknown-store"
	if deliver(unknown) != 200 || balance("u") != 405 {
		t.Fatal("unknown product minted coins")
	}
	exec(`INSERT INTO coin_packs(id,key,name,environment,platform,coins,product_id) VALUES('custom-coin','custom-coin','Custom coin','prod','app',77,'custom.coin.pack')`)
	exec(`UPDATE revenuecat_webhook_events SET retry_at=CURRENT_TIMESTAMP WHERE id='unknown-product-event'`)
	if err := ProcessRevenueCatWebhookJobs(t.Context()); err != nil || balance("u") != 482 {
		t.Fatalf("catalog repair: balance %d err %v", balance("u"), err)
	}

	// A direct grant also serializes keys under concurrent calls, protecting annual installments.
	grantErrors := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := grantCreditsForPlatform("u", 13, "grant", "concurrent-grant", "app", false)
			grantErrors <- err
		}()
	}
	wg.Wait()
	close(grantErrors)
	for err := range grantErrors {
		if err != nil {
			t.Fatal(err)
		}
	}
	if balance("u") != 495 {
		t.Fatal("generic grant key did not serialize concurrent calls")
	}
}

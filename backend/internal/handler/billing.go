package handler

import (
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

// --- Billing: Credits + Subscriptions ---
//
// Mobile: RevenueCat wraps Apple/Google billing. The RC webhook syncs
// subscriptions and grants monthly credits here. Web/admin: Stripe (REST API,
// no SDK dependency). Stripe cannot be used for in-app digital goods; it only
// serves the web side of the product.

// BillingConfig carries the runtime billing settings (set at startup).
type BillingConfig struct {
	RevenueCatWebhookSecret    string
	StripeSecretKey            string
	StripeWebhookSecret        string
	StripePricePlus            string
	StripePricePremium         string
	SubscriptionCreditsMonthly int
}

var billingCfg BillingConfig

// InitBilling is called at startup.
func InitBilling(cfg BillingConfig) { billingCfg = cfg }

// ============================= Credits =============================

type CreditTx struct {
	ID           string    `json:"id"`
	Amount       int       `json:"amount"`
	BalanceAfter int       `json:"balance_after"`
	Kind         string    `json:"kind"`
	Description  string    `json:"description"`
	CreatedAt    time.Time `json:"created_at"`
}

type CreditsResponse struct {
	Balance      int        `json:"balance"`
	Transactions []CreditTx `json:"transactions"`
}

// GetCredits returns the user's credit balance and recent transactions.
func GetCredits(c *gin.Context) {
	userID := c.GetString("user_id")

	var balance int
	if err := db.Get().QueryRow(
		`SELECT COALESCE(credits_balance, 0) FROM users WHERE id = $1`, userID).Scan(&balance); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load credits"})
		return
	}

	rows, err := db.Get().Query(
		`SELECT id, amount, balance_after, kind, COALESCE(description, ''), created_at
		 FROM credit_transactions WHERE user_id = $1
		 ORDER BY created_at DESC, id DESC LIMIT 50`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load transactions"})
		return
	}
	defer rows.Close()

	txs := []CreditTx{}
	for rows.Next() {
		var tx CreditTx
		if err := rows.Scan(&tx.ID, &tx.Amount, &tx.BalanceAfter, &tx.Kind, &tx.Description, &tx.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan transactions"})
			return
		}
		txs = append(txs, tx)
	}
	c.JSON(http.StatusOK, CreditsResponse{Balance: balance, Transactions: txs})
}

type ConsumeCreditsRequest struct {
	Amount      int    `json:"amount" binding:"required,min=1"`
	Description string `json:"description"`
}

// ConsumeCredits deducts credits (called by future paid features such as
// high-quality images / long voice). It is atomic and balance-checked.
func ConsumeCredits(c *gin.Context) {
	userID := c.GetString("user_id")

	var req ConsumeCreditsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tx, err := db.Get().Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start transaction"})
		return
	}
	defer tx.Rollback()

	var balance int
	if err := tx.QueryRow(
		`SELECT COALESCE(credits_balance, 0) FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&balance); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load credits"})
		return
	}
	if balance < req.Amount {
		c.JSON(http.StatusBadRequest, gin.H{"error": "insufficient credits"})
		return
	}

	newBalance := balance - req.Amount
	if _, err := tx.Exec(
		`UPDATE users SET credits_balance = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`,
		newBalance, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update credits"})
		return
	}
	if _, err := tx.Exec(
		`INSERT INTO credit_transactions (id, user_id, amount, balance_after, kind, description, platform, environment)
		 VALUES ($1, $2, $3, $4, 'consume', $5, $6, $7)`,
		uuid.New().String(), userID, -req.Amount, newBalance, req.Description,
		requestPlatform(c), currentEnvironment()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record transaction"})
		return
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to commit"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"balance": newBalance})
}

// grantCredits credits the user and records a transaction. When dedupeKey is
// non-empty, an identical grant is skipped (webhook retry safety). Returns the
// resulting balance.
func grantCredits(userID string, amount int, kind, dedupeKey string) (int, error) {
	return grantCreditsForPlatform(userID, amount, kind, dedupeKey, "system")
}

func grantCreditsForPlatform(userID string, amount int, kind, dedupeKey, platform string) (int, error) {
	if amount == 0 {
		var bal int
		err := db.Get().QueryRow(
			`SELECT COALESCE(credits_balance, 0) FROM users WHERE id = $1`, userID).Scan(&bal)
		return bal, err
	}

	if dedupeKey != "" {
		var exists bool
		if err := db.Get().QueryRow(
			`SELECT EXISTS(SELECT 1 FROM credit_transactions WHERE user_id = $1 AND description = $2)`,
			userID, dedupeKey).Scan(&exists); err != nil {
			return 0, err
		}
		if exists {
			var bal int
			err := db.Get().QueryRow(
				`SELECT COALESCE(credits_balance, 0) FROM users WHERE id = $1`, userID).Scan(&bal)
			return bal, err
		}
	}

	tx, err := db.Get().Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	var bal int
	if err := tx.QueryRow(
		`UPDATE users SET credits_balance = credits_balance + $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2 RETURNING credits_balance`,
		amount, userID).Scan(&bal); err != nil {
		return 0, err
	}

	desc := dedupeKey
	if desc == "" {
		desc = "credits granted"
	}
	if _, err := tx.Exec(
		`INSERT INTO credit_transactions (id, user_id, amount, balance_after, kind, description, platform, environment)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		uuid.New().String(), userID, amount, bal, kind, desc, platform, currentEnvironment()); err != nil {
		return 0, err
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return bal, nil
}

func requestPlatform(c *gin.Context) string {
	switch strings.ToLower(strings.TrimSpace(c.GetHeader("X-Vita-Platform"))) {
	case "ios", "android", "web":
		return strings.ToLower(strings.TrimSpace(c.GetHeader("X-Vita-Platform")))
	default:
		return "system"
	}
}

// ============================= Subscriptions =============================

type Subscription struct {
	ID               string     `json:"id"`
	Provider         string     `json:"provider"`
	ProviderRef      string     `json:"provider_ref"`
	ProductID        string     `json:"product_id"`
	Entitlement      string     `json:"entitlement"`
	Status           string     `json:"status"`
	CurrentPeriodEnd *time.Time `json:"current_period_end"`
	WillRenew        bool       `json:"will_renew"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

// upsertSubscription inserts or updates a subscription identified by
// (provider, provider_ref). Returns the row.
func upsertSubscription(userID, provider, providerRef, productID, entitlement, status, platform string,
	periodStart, periodEnd *time.Time, willRenew bool) (*Subscription, error) {

	if _, err := db.Get().Exec(
		`INSERT INTO subscriptions
		   (id, user_id, provider, provider_ref, product_id, entitlement, status, platform, environment,
		    current_period_start, current_period_end, will_renew, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, CURRENT_TIMESTAMP)
		 ON CONFLICT (provider, provider_ref) DO UPDATE SET
		   user_id = EXCLUDED.user_id,
		   product_id = CASE WHEN EXCLUDED.product_id <> '' THEN EXCLUDED.product_id ELSE subscriptions.product_id END,
		   entitlement = CASE WHEN EXCLUDED.entitlement <> '' THEN EXCLUDED.entitlement ELSE subscriptions.entitlement END,
		   status = EXCLUDED.status,
		   platform = EXCLUDED.platform,
		   environment = EXCLUDED.environment,
		   current_period_start = EXCLUDED.current_period_start,
		   current_period_end = EXCLUDED.current_period_end,
		   will_renew = EXCLUDED.will_renew,
		   updated_at = CURRENT_TIMESTAMP`,
		uuid.New().String(), userID, provider, providerRef, productID, entitlement, status, platform,
		currentEnvironment(), periodStart, periodEnd, willRenew); err != nil {
		return nil, err
	}

	subscription, err := loadSubscription(provider, providerRef)
	if err != nil {
		return nil, err
	}
	if active, accessErr := userHasActiveSubscription(userID); accessErr == nil {
		_ = syncUserCompanionEntitlement(userID, active)
	}
	return subscription, nil
}

func loadSubscription(provider, providerRef string) (*Subscription, error) {
	var s Subscription
	err := db.Get().QueryRow(
		`SELECT id, provider, provider_ref, COALESCE(product_id, ''), COALESCE(entitlement, ''),
		        status, current_period_end, will_renew, created_at, updated_at
		 FROM subscriptions WHERE provider = $1 AND provider_ref = $2`,
		provider, providerRef).
		Scan(&s.ID, &s.Provider, &s.ProviderRef, &s.ProductID, &s.Entitlement,
			&s.Status, &s.CurrentPeriodEnd, &s.WillRenew, &s.CreatedAt, &s.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// GetMySubscription returns the user's current active subscription and the
// entitlements it grants.
func GetMySubscription(c *gin.Context) {
	userID := c.GetString("user_id")
	if active, accessErr := userHasActiveSubscription(userID); accessErr == nil {
		_ = syncUserCompanionEntitlement(userID, active)
	}

	var s Subscription
	err := db.Get().QueryRow(
		`SELECT id, provider, provider_ref, COALESCE(product_id, ''), COALESCE(entitlement, ''),
		        status, current_period_end, will_renew, created_at, updated_at
		 FROM subscriptions WHERE user_id = $1
		 ORDER BY updated_at DESC LIMIT 1`,
		userID).
		Scan(&s.ID, &s.Provider, &s.ProviderRef, &s.ProductID, &s.Entitlement,
			&s.Status, &s.CurrentPeriodEnd, &s.WillRenew, &s.CreatedAt, &s.UpdatedAt)

	entitlements := []string{}
	if err == nil && s.Status == "active" &&
		(s.CurrentPeriodEnd == nil || s.CurrentPeriodEnd.After(time.Now())) {
		if s.Entitlement != "" {
			entitlements = append(entitlements, s.Entitlement)
		}
		c.JSON(http.StatusOK, gin.H{"subscription": s, "entitlements": entitlements})
		return
	}
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load subscription"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"subscription": nil, "entitlements": entitlements})
}

// ============================= RevenueCat webhook =============================

// RevenueCat sends webhook events signed with the shared secret in the
// Authorization header. Events keep our subscriptions table and credit balance
// in sync with Apple / Google billing.

type revenueCatWebhookPayload struct {
	Event *revenueCatEvent `json:"event"`
	// "test" for sandbox API events; we process them the same way.
	APIVersion string `json:"api_version"`
}

type revenueCatEvent struct {
	Type                  string `json:"type"`
	AppUserID             string `json:"app_user_id"`
	ProductID             string `json:"product_id"`
	EntitlementID         string `json:"entitlement_id"`
	PeriodType            string `json:"period_type"`
	PurchasedAtMS         int64  `json:"purchased_at_ms"`
	ExpirationAtMS        int64  `json:"expiration_at_ms"`
	OriginalTransactionID string `json:"original_transaction_id"`
	Store                 string `json:"store"`
	NewAppUserID          string `json:"new_app_user_id"`
}

// RevenueCatWebhook processes RevenueCat server-to-server events.
func RevenueCatWebhook(c *gin.Context) {
	if billingCfg.RevenueCatWebhookSecret != "" {
		auth := c.GetHeader("Authorization")
		expected := "Bearer " + billingCfg.RevenueCatWebhookSecret
		if !hmac.Equal([]byte(auth), []byte(expected)) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid webhook secret"})
			return
		}
	}

	var payload revenueCatWebhookPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload"})
		return
	}
	ev := payload.Event
	if ev == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing event"})
		return
	}
	// RevenueCat expects a fast 2xx; processing errors are logged, not returned.
	processRevenueCatEvent(ev)
	c.JSON(http.StatusOK, gin.H{"received": true})
}

func processRevenueCatEvent(ev *revenueCatEvent) {
	userID := ev.AppUserID
	if userID == "" {
		return
	}

	switch ev.Type {
	case "TRANSFER":
		// Ownership moved to another app user id.
		if ev.NewAppUserID != "" {
			_, _ = db.Get().Exec(
				`UPDATE subscriptions SET app_user_id = $1, updated_at = CURRENT_TIMESTAMP WHERE app_user_id = $2`,
				ev.NewAppUserID, userID)
		}
		return
	}

	platform := platformFromRevenueCatStore(ev.Store)
	purchasedAt := time.Now()
	if ev.PurchasedAtMS > 0 {
		purchasedAt = time.UnixMilli(ev.PurchasedAtMS)
	}
	purchaseRef := fmt.Sprintf("%s:%d", ev.OriginalTransactionID, ev.PurchasedAtMS)

	// Consumables: grant credits for product ids like "credits_500".
	if ev.Type == "NON_RENEWING_PURCHASE" || ev.Type == "INITIAL_PURCHASE" {
		amount, configured := configuredProductCredits("coin_packs", ev.ProductID, platform)
		if !configured {
			amount = creditsFromProductID(ev.ProductID)
		}
		if amount > 0 {
			dedupe := fmt.Sprintf("rc-purchase:%s:%d", ev.OriginalTransactionID, ev.PurchasedAtMS)
			if _, err := grantCreditsForPlatform(userID, amount, "purchase", dedupe, platform); err != nil {
				fmt.Printf("revenuecat: failed to grant credits for %s: %v\n", userID, err)
			}
			recordPurchase(userID, purchaseRef, "coin_pack", "revenuecat", platform, ev.ProductID, nil, "", amount, "paid", purchasedAt)
			return
		}
	}

	// Subscription lifecycle.
	if ev.OriginalTransactionID == "" {
		return
	}
	ref := ev.OriginalTransactionID
	entitlement := ev.EntitlementID
	status := "active"
	willRenew := true

	switch ev.Type {
	case "INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE":
		status = "active"
		willRenew = true
		// Grant monthly credits on real (non-trial) purchase / renewal. A trial
		// becomes a purchase on the RENEWAL that follows it.
		credits, configured := configuredProductCredits("subscription_plans", ev.ProductID, platform)
		if !configured {
			credits = billingCfg.SubscriptionCreditsMonthly
		}
		if credits > 0 && ev.PeriodType != "TRIAL" {
			dedupe := fmt.Sprintf("rc-subscription:%s:%d", ref, ev.PurchasedAtMS)
			if _, err := grantCreditsForPlatform(userID, credits, "grant", dedupe, platform); err != nil {
				fmt.Printf("revenuecat: failed to grant monthly credits for %s: %v\n", userID, err)
			}
		}
	case "CANCELLATION":
		status = "cancelled"
		willRenew = false
	case "EXPIRATION":
		status = "expired"
		willRenew = false
	case "SUBSCRIPTION_PAUSED":
		status = "paused"
		willRenew = false
	default:
		// BILLING_ISSUES, PRODUCT_CHANGE and friends: keep current state.
		return
	}

	var periodStart, periodEnd *time.Time
	if ev.PurchasedAtMS > 0 {
		t := time.UnixMilli(ev.PurchasedAtMS)
		periodStart = &t
	}
	if ev.ExpirationAtMS > 0 {
		t := time.UnixMilli(ev.ExpirationAtMS)
		periodEnd = &t
	}

	if _, err := upsertSubscription(userID, "revenuecat", ref, ev.ProductID, entitlement,
		status, platform, periodStart, periodEnd, willRenew); err != nil {
		fmt.Printf("revenuecat: failed to upsert subscription for %s: %v\n", userID, err)
	}
	if ev.Type == "INITIAL_PURCHASE" || ev.Type == "RENEWAL" {
		credits, configured := configuredProductCredits("subscription_plans", ev.ProductID, platform)
		if !configured {
			credits = billingCfg.SubscriptionCreditsMonthly
		}
		recordPurchase(userID, purchaseRef, "subscription", "revenuecat", platform, ev.ProductID,
			nil, "", credits, "paid", purchasedAt)
	}
}

func configuredProductCredits(table, productID, platform string) (int, bool) {
	if productID == "" || (table != "coin_packs" && table != "subscription_plans") {
		return 0, false
	}
	coinColumn := "coins"
	if table == "subscription_plans" {
		coinColumn = "coins_granted"
	}
	var credits int
	err := db.Get().QueryRow(`SELECT `+coinColumn+` FROM `+table+
		` WHERE environment=$1 AND platform=$2 AND product_id=$3 AND enabled=true LIMIT 1`,
		currentEnvironment(), platform, productID).Scan(&credits)
	if err != nil {
		return 0, false
	}
	return credits, true
}

func platformFromRevenueCatStore(store string) string {
	switch strings.ToUpper(strings.TrimSpace(store)) {
	case "APP_STORE", "MAC_APP_STORE":
		return "ios"
	case "PLAY_STORE", "AMAZON":
		return "android"
	case "STRIPE":
		return "web"
	default:
		return "system"
	}
}

func recordPurchase(userID, transactionID, kind, provider, platform, productID string, amountMinor *int64,
	currency string, credits int, status string, purchasedAt time.Time) {
	if userID == "" || transactionID == "" {
		return
	}
	_, err := db.Get().Exec(
		`INSERT INTO billing_purchases
		 (id, user_id, transaction_id, kind, provider, platform, environment, product_id,
		  amount_minor, currency, credits, status, purchased_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		 ON CONFLICT (provider, transaction_id) DO UPDATE SET
		  status = EXCLUDED.status, amount_minor = COALESCE(EXCLUDED.amount_minor, billing_purchases.amount_minor),
		  currency = CASE WHEN EXCLUDED.currency <> '' THEN EXCLUDED.currency ELSE billing_purchases.currency END`,
		uuid.New().String(), userID, transactionID, kind, provider, platform, currentEnvironment(), productID,
		amountMinor, strings.ToUpper(currency), credits, status, purchasedAt)
	if err != nil {
		fmt.Printf("billing: failed to record purchase %s: %v\n", transactionID, err)
	}
}

// creditsFromProductID maps product ids such as "credits_500" / "coins_1000" to
// their credit amount. Returns 0 when the product is not a credit pack.
func creditsFromProductID(productID string) int {
	if productID == "" {
		return 0
	}
	lower := strings.ToLower(productID)
	for _, prefix := range []string{"credits_", "coins_"} {
		if strings.HasPrefix(lower, prefix) {
			if n, err := strconv.Atoi(strings.TrimPrefix(lower, prefix)); err == nil && n > 0 {
				return n
			}
		}
	}
	return 0
}

// ============================= Stripe (web / admin) =============================

// Stripe is only wired to the web side of the product (checkout sessions), per
// store policy for in-app digital goods.

type CreateCheckoutRequest struct {
	Plan string `json:"plan" binding:"required"`
}

// CreateStripeCheckout creates a Stripe Checkout Session for the current user.
func CreateStripeCheckout(c *gin.Context) {
	userID := c.GetString("user_id")

	var req CreateCheckoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if billingCfg.StripeSecretKey == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "stripe is not configured"})
		return
	}

	var priceID string
	err := db.Get().QueryRow(`SELECT product_id FROM subscription_plans
		WHERE environment=$1 AND platform='web' AND key=$2 AND enabled=true LIMIT 1`,
		currentEnvironment(), req.Plan).Scan(&priceID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		// Keep legacy Stripe checkout working during an additive deployment
		// before the product-catalog migration has reached the shared database.
		fmt.Printf("billing: subscription plan lookup unavailable: %v\n", err)
	}
	if priceID == "" {
		switch req.Plan {
		case "plus":
			priceID = billingCfg.StripePricePlus
		case "premium":
			priceID = billingCfg.StripePricePremium
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "unknown subscription plan"})
			return
		}
	}
	if priceID == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "stripe price not configured"})
		return
	}

	var userEmail string
	_ = db.Get().QueryRow(`SELECT email FROM users WHERE id = $1`, userID).Scan(&userEmail)

	form := url.Values{}
	form.Set("mode", "subscription")
	form.Set("line_items[0][price]", priceID)
	form.Set("line_items[0][quantity]", "1")
	form.Set("success_url", "https://vita.app/pay/success?session_id={CHECKOUT_SESSION_ID}")
	form.Set("cancel_url", "https://vita.app/pay/cancel")
	form.Set("client_reference_id", userID)
	form.Set("metadata[plan]", req.Plan)
	form.Set("metadata[user_id]", userID)
	if userEmail != "" {
		form.Set("customer_email", userEmail)
	}

	body, err := stripeRequest(http.MethodPost, "/v1/checkout/sessions", &form)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "stripe request failed"})
		return
	}
	var session struct {
		ID  string `json:"id"`
		URL string `json:"url"`
	}
	if err := json.Unmarshal(body, &session); err != nil || session.URL == "" {
		c.JSON(http.StatusBadGateway, gin.H{"error": "invalid stripe response"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"session_id": session.ID, "url": session.URL})
}

// StripeWebhook verifies the signature and syncs subscription lifecycle events
// into the same subscriptions table (provider = "stripe").
func StripeWebhook(c *gin.Context) {
	raw, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read body"})
		return
	}
	if billingCfg.StripeWebhookSecret != "" {
		sig := c.GetHeader("Stripe-Signature")
		if !verifyStripeSignature(raw, sig, billingCfg.StripeWebhookSecret) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid signature"})
			return
		}
	}

	var payload struct {
		Type string `json:"type"`
		Data struct {
			Object json.RawMessage `json:"object"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payload"})
		return
	}

	switch payload.Type {
	case "checkout.session.completed":
		processStripeSessionCompleted(payload.Data.Object)
	case "invoice.paid":
		processStripeInvoicePaid(payload.Data.Object)
	case "customer.subscription.updated", "customer.subscription.deleted":
		processStripeSubscriptionEvent(payload.Type, payload.Data.Object)
	}
	c.JSON(http.StatusOK, gin.H{"received": true})
}

type stripeSession struct {
	ID                string            `json:"id"`
	ClientReferenceID string            `json:"client_reference_id"`
	Subscription      string            `json:"subscription"`
	Metadata          map[string]string `json:"metadata"`
	Customer          string            `json:"customer"`
	AmountTotal       int64             `json:"amount_total"`
	Currency          string            `json:"currency"`
	PaymentStatus     string            `json:"payment_status"`
}

func processStripeSessionCompleted(obj json.RawMessage) {
	var session stripeSession
	if err := json.Unmarshal(obj, &session); err != nil {
		return
	}
	userID := session.ClientReferenceID
	if userID == "" {
		userID = session.Metadata["user_id"]
	}
	plan := session.Metadata["plan"]
	if userID == "" || plan == "" || session.Subscription == "" {
		return
	}

	// Pull period details from the subscription object.
	subBody, err := stripeRequest(http.MethodGet, "/v1/subscriptions/"+session.Subscription, nil)
	if err != nil {
		fmt.Printf("stripe: failed to fetch subscription %s: %v\n", session.Subscription, err)
		return
	}
	var stripeSub struct {
		ID               string `json:"id"`
		Status           string `json:"status"`
		CurrentPeriodEnd int64  `json:"current_period_end"`
		Items            struct {
			Data []struct {
				Price struct {
					ID string `json:"id"`
				} `json:"price"`
			} `json:"data"`
		} `json:"items"`
	}
	if err := json.Unmarshal(subBody, &stripeSub); err != nil {
		return
	}

	status := "active"
	if stripeSub.Status != "active" && stripeSub.Status != "trialing" {
		status = stripeSub.Status
	}
	periodEnd := time.Unix(stripeSub.CurrentPeriodEnd, 0)
	productID := ""
	if len(stripeSub.Items.Data) > 0 {
		productID = stripeSub.Items.Data[0].Price.ID
	}

	if _, err := upsertSubscription(userID, "stripe", stripeSub.ID, productID, plan,
		status, "web", nil, &periodEnd, true); err != nil {
		fmt.Printf("stripe: failed to upsert subscription: %v\n", err)
		return
	}

	// One-time grant on first completion of the subscription.
	credits, configured := configuredProductCredits("subscription_plans", productID, "web")
	if !configured {
		credits = billingCfg.SubscriptionCreditsMonthly
	}
	dedupe := "stripe-subscription:" + stripeSub.ID + ":initial"
	if _, err := grantCreditsForPlatform(userID, credits, "grant", dedupe, "web"); err != nil {
		fmt.Printf("stripe: failed to grant credits: %v\n", err)
	}
	recordPurchase(userID, session.ID, "subscription", "stripe", "web", productID,
		&session.AmountTotal, session.Currency, credits, session.PaymentStatus, time.Now())
}

type stripeInvoice struct {
	ID            string `json:"id"`
	Subscription  string `json:"subscription"`
	Status        string `json:"status"`
	Paid          bool   `json:"paid"`
	Customer      string `json:"customer"`
	CustomerEmail string `json:"customer_email"`
	AmountPaid    int64  `json:"amount_paid"`
	Currency      string `json:"currency"`
	Lines         struct {
		Data []struct {
			Price struct {
				ID string `json:"id"`
			} `json:"price"`
			Period struct {
				Start int64 `json:"start"`
				End   int64 `json:"end"`
			} `json:"period"`
		} `json:"data"`
	} `json:"lines"`
}

func processStripeInvoicePaid(obj json.RawMessage) {
	var inv stripeInvoice
	if err := json.Unmarshal(obj, &inv); err != nil {
		return
	}
	if !inv.Paid || inv.Subscription == "" {
		return
	}

	// Resolve the user from the subscription (metadata carries the user id
	// created by the checkout session).
	subBody, err := stripeRequest(http.MethodGet, "/v1/subscriptions/"+inv.Subscription, nil)
	if err != nil {
		return
	}
	var stripeSub struct {
		Customer string            `json:"customer"`
		Metadata map[string]string `json:"metadata"`
	}
	if err := json.Unmarshal(subBody, &stripeSub); err != nil {
		return
	}
	var userIDResolved string
	if stripeSub.Metadata["user_id"] != "" {
		userIDResolved = stripeSub.Metadata["user_id"]
	} else {
		// resolve customer email
		custBody, err := stripeRequest(http.MethodGet, "/v1/customers/"+stripeSub.Customer, nil)
		if err == nil {
			var cust struct {
				Email string `json:"email"`
			}
			if json.Unmarshal(custBody, &cust) == nil && cust.Email != "" {
				_ = db.Get().QueryRow(`SELECT id FROM users WHERE email = $1`, cust.Email).Scan(&userIDResolved)
			}
		}
	}
	if userIDResolved == "" {
		return
	}

	// Renewal: refresh period and grant monthly credits once per invoice.
	var subPeriodEnd *time.Time
	if len(inv.Lines.Data) > 0 && inv.Lines.Data[0].Period.End > 0 {
		t := time.Unix(inv.Lines.Data[0].Period.End, 0)
		subPeriodEnd = &t
	}
	periodStart := time.Now()
	productID := ""
	if len(inv.Lines.Data) > 0 && inv.Lines.Data[0].Period.Start > 0 {
		periodStart = time.Unix(inv.Lines.Data[0].Period.Start, 0)
	}
	if len(inv.Lines.Data) > 0 {
		productID = inv.Lines.Data[0].Price.ID
	}
	if _, err := upsertSubscription(userIDResolved, "stripe", inv.Subscription, productID, "",
		"active", "web", &periodStart, subPeriodEnd, true); err != nil {
		return
	}
	dedupe := "stripe-subscription:" + inv.Subscription + ":" + inv.ID
	credits, configured := configuredProductCredits("subscription_plans", productID, "web")
	if !configured {
		credits = billingCfg.SubscriptionCreditsMonthly
	}
	if _, err := grantCreditsForPlatform(userIDResolved, credits, "grant", dedupe, "web"); err != nil {
		fmt.Printf("stripe: failed to grant renewal credits: %v\n", err)
	}
	recordPurchase(userIDResolved, inv.ID, "subscription", "stripe", "web", productID,
		&inv.AmountPaid, inv.Currency, credits, "paid", periodStart)
}

func processStripeSubscriptionEvent(eventType string, obj json.RawMessage) {
	var sub struct {
		ID                string `json:"id"`
		Status            string `json:"status"`
		CancelAtPeriodEnd bool   `json:"cancel_at_period_end"`
	}
	if err := json.Unmarshal(obj, &sub); err != nil || sub.ID == "" {
		return
	}
	status := "active"
	willRenew := true
	switch sub.Status {
	case "active", "trialing":
		status = "active"
		willRenew = true
	case "canceled":
		status = "expired"
		willRenew = false
	case "unpaid", "past_due":
		status = "paused"
		willRenew = false
	default:
		status = sub.Status
	}
	if eventType == "customer.subscription.deleted" {
		status = "expired"
		willRenew = false
	} else if sub.CancelAtPeriodEnd {
		status = "cancelled"
		willRenew = false
	}
	var userID string
	err := db.Get().QueryRow(
		`UPDATE subscriptions SET status = $1, will_renew = $2, updated_at = CURRENT_TIMESTAMP
		 WHERE provider = 'stripe' AND provider_ref = $3 RETURNING user_id`,
		status, willRenew, sub.ID).Scan(&userID)
	if err == nil {
		if active, accessErr := userHasActiveSubscription(userID); accessErr == nil {
			_ = syncUserCompanionEntitlement(userID, active)
		}
	}
}

// stripeRequest performs a REST call to the Stripe API (no SDK dependency).
func stripeRequest(method, path string, form *url.Values) ([]byte, error) {
	client := &http.Client{Timeout: 15 * time.Second}
	req, err := http.NewRequest(method, "https://api.stripe.com"+path, nil)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(billingCfg.StripeSecretKey, "")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if form != nil {
		req.Body = io.NopCloser(strings.NewReader(form.Encode()))
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("stripe %s: %s", path, string(body))
	}
	return body, nil
}

// verifyStripeSignature checks the Stripe-Signature header (t=...,v1=...)
// against the webhook signing secret.
func verifyStripeSignature(payload []byte, header, secret string) bool {
	parts := map[string]string{}
	for _, item := range strings.Split(header, ",") {
		kv := strings.SplitN(strings.TrimSpace(item), "=", 2)
		if len(kv) == 2 {
			parts[kv[0]] = kv[1]
		}
	}
	t, okT := parts["t"]
	v1, okV1 := parts["v1"]
	if !okT || !okV1 {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(t + "." + string(payload)))
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(v1))
}

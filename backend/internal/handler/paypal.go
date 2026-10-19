package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"vita/internal/db"
	"vita/internal/paypal"
)

type PayPalConfig struct {
	ClientID, Secret, WebhookID, Mode, WebURL string
	Plans                                     map[string]string
}

var paypalCfg PayPalConfig

func InitPayPal(cfg PayPalConfig) { paypalCfg = cfg }
func paypalClient() paypal.Client {
	endpoint := "https://api-m.sandbox.paypal.com"
	if paypalCfg.Mode == "live" {
		endpoint = "https://api-m.paypal.com"
	}
	return paypal.Client{ClientID: paypalCfg.ClientID, Secret: paypalCfg.Secret, BaseURL: endpoint}
}
func paypalAvailable() bool {
	u, err := url.Parse(paypalCfg.WebURL)
	return paypalCfg.ClientID != "" && paypalCfg.Secret != "" && paypalCfg.WebhookID != "" && (paypalCfg.Mode == "sandbox" || paypalCfg.Mode == "live") && err == nil && u.Host != "" && (u.Scheme == "https" || (paypalCfg.Mode == "sandbox" && u.Scheme == "http" && (u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1")))
}

type paypalProduct struct {
	Key       string `json:"key"`
	Name      string `json:"name"`
	Kind      string `json:"kind"`
	ProductID string `json:"-"`
	Price     string `json:"price_usd"`
	Coins     int    `json:"coins"`
	Period    string `json:"period"`
}

func paypalProducts(ctx context.Context) ([]paypalProduct, error) {
	rows, err := db.Get().QueryContext(ctx, `SELECT key,name,'coin',product_id,ROUND(price_usd::numeric,2)::text,coins,'' FROM coin_packs WHERE environment=$1 AND platform='web' AND enabled=true AND price_usd>0 UNION ALL SELECT key,name,'subscription',product_id,ROUND(price_usd::numeric,2)::text,coins_granted,period FROM subscription_plans WHERE environment=$1 AND platform='web' AND enabled=true AND price_usd>0 AND product_id<>'' ORDER BY 3,5`, currentEnvironment())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []paypalProduct{}
	for rows.Next() {
		var p paypalProduct
		if err := rows.Scan(&p.Key, &p.Name, &p.Kind, &p.ProductID, &p.Price, &p.Coins, &p.Period); err != nil {
			return nil, err
		}
		if p.Kind == "subscription" && paypalCfg.Plans[p.Key] == "" {
			continue
		}
		result = append(result, p)
	}
	return result, rows.Err()
}
func PayPalCatalog(c *gin.Context) {
	p, err := paypalProducts(c.Request.Context())
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to load PayPal catalog"})
		return
	}
	c.JSON(200, gin.H{"available": paypalAvailable(), "mode": paypalCfg.Mode, "items": p})
}

var paypalMoney = regexp.MustCompile(`^[0-9]+\.[0-9]{2}$`)

func paypalMinor(value string) (int64, error) {
	if !paypalMoney.MatchString(value) {
		return 0, errors.New("invalid USD amount")
	}
	parts := strings.Split(value, ".")
	whole, err := strconv.ParseInt(parts[0], 10, 54)
	if err != nil {
		return 0, err
	}
	fraction, _ := strconv.ParseInt(parts[1], 10, 8)
	return whole*100 + fraction, nil
}
func paypalValue(minor int64) string { return fmt.Sprintf("%d.%02d", minor/100, minor%100) }

type paypalCheckout struct {
	ID, User, Kind, Key, Product, Plan, Period, Provider, Approval, State string
	Amount                                                                int64
	Coins                                                                 int
	Created                                                               time.Time
}

const paypalCheckoutColumns = `id,user_id,kind,product_key,product_id,paypal_plan_id,period,COALESCE(provider_id,''),approval_url,state,amount_minor,coins,created_at`

func scanPayPalCheckout(row interface{ Scan(...any) error }) (paypalCheckout, error) {
	var v paypalCheckout
	err := row.Scan(&v.ID, &v.User, &v.Kind, &v.Key, &v.Product, &v.Plan, &v.Period, &v.Provider, &v.Approval, &v.State, &v.Amount, &v.Coins, &v.Created)
	return v, err
}
func CreatePayPalCheckout(c *gin.Context) {
	if !paypalAvailable() {
		c.JSON(503, gin.H{"error": "PayPal is not configured"})
		return
	}
	var input struct {
		Key        string `json:"product_key"`
		Kind       string `json:"kind"`
		RequestKey string `json:"idempotency_key"`
	}
	if c.ShouldBindJSON(&input) != nil || len(input.RequestKey) < 16 || len(input.RequestKey) > 100 || (input.Kind != "coin" && input.Kind != "subscription") {
		c.JSON(400, gin.H{"error": "invalid checkout request"})
		return
	}
	products, err := paypalProducts(c.Request.Context())
	if err != nil {
		c.JSON(503, gin.H{"error": "catalog unavailable"})
		return
	}
	var product *paypalProduct
	for i := range products {
		if products[i].Key == input.Key && products[i].Kind == input.Kind {
			product = &products[i]
			break
		}
	}
	if product == nil {
		c.JSON(400, gin.H{"error": "product unavailable"})
		return
	}
	amount, err := paypalMinor(product.Price)
	if err != nil || amount <= 0 {
		c.JSON(503, gin.H{"error": "invalid product price"})
		return
	}
	if input.Kind == "subscription" {
		var active bool
		err = db.Get().QueryRowContext(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM subscriptions WHERE user_id=$1 AND status='active' AND (current_period_end IS NULL OR current_period_end>CURRENT_TIMESTAMP))`, c.GetString("user_id")).Scan(&active)
		if err != nil || active {
			c.JSON(409, gin.H{"error": "an active membership already exists"})
			return
		}
	}
	// Serialize reservations per account so two tabs cannot create two recurring subscriptions.
	reservation, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(503, gin.H{"error": "checkout reservation unavailable"})
		return
	}
	defer reservation.Rollback()
	var lockedUser string
	if err = reservation.QueryRowContext(c.Request.Context(), `SELECT id FROM users WHERE id=$1 FOR UPDATE`, c.GetString("user_id")).Scan(&lockedUser); err != nil {
		c.JSON(503, gin.H{"error": "account unavailable"})
		return
	}
	if input.Kind == "subscription" {
		var active bool
		err = reservation.QueryRowContext(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM subscriptions WHERE user_id=$1 AND status='active' AND (current_period_end IS NULL OR current_period_end>CURRENT_TIMESTAMP))`, lockedUser).Scan(&active)
		if err != nil || active {
			c.JSON(409, gin.H{"error": "an active membership already exists"})
			return
		}
		var pendingID, pendingKey, pendingProduct, pendingURL string
		err = reservation.QueryRowContext(c.Request.Context(), `SELECT id,request_key,product_key,approval_url FROM paypal_checkouts WHERE user_id=$1 AND kind='subscription' AND state IN ('created','approval_pending') ORDER BY created_at LIMIT 1`, lockedUser).Scan(&pendingID, &pendingKey, &pendingProduct, &pendingURL)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			c.JSON(503, gin.H{"error": "pending checkout unavailable"})
			return
		}
		if err == nil && pendingKey != input.RequestKey {
			if pendingProduct == input.Key && pendingURL != "" {
				c.JSON(200, gin.H{"id": pendingID, "url": pendingURL, "status": "approval_pending"})
			} else {
				c.JSON(409, gin.H{"error": "finish the pending subscription checkout before starting another"})
			}
			return
		}
	}
	checkoutID := uuid.New().String()
	_, err = reservation.ExecContext(c.Request.Context(), `INSERT INTO paypal_checkouts(id,user_id,request_key,kind,product_key,product_id,paypal_plan_id,amount_minor,coins,period) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(user_id,request_key) DO NOTHING`, checkoutID, c.GetString("user_id"), input.RequestKey, input.Kind, input.Key, product.ProductID, paypalCfg.Plans[input.Key], amount, product.Coins, product.Period)
	if err != nil {
		c.JSON(503, gin.H{"error": "failed to save checkout"})
		return
	}
	if err = reservation.Commit(); err != nil {
		c.JSON(503, gin.H{"error": "failed to reserve checkout"})
		return
	}
	checkout, err := scanPayPalCheckout(db.Get().QueryRowContext(c.Request.Context(), `SELECT `+paypalCheckoutColumns+` FROM paypal_checkouts WHERE user_id=$1 AND request_key=$2`, c.GetString("user_id"), input.RequestKey))
	if err != nil {
		c.JSON(503, gin.H{"error": "checkout unavailable"})
		return
	}
	if checkout.Kind != input.Kind || checkout.Key != input.Key {
		c.JSON(409, gin.H{"error": "request key already used for another product"})
		return
	}
	if time.Since(checkout.Created) > 6*time.Hour {
		c.JSON(409, gin.H{"error": "checkout expired; create a new checkout"})
		return
	}
	if checkout.Provider != "" {
		c.JSON(200, gin.H{"id": checkout.ID, "url": checkout.Approval, "status": checkout.State})
		return
	}
	returnURL := strings.TrimRight(paypalCfg.WebURL, "/") + "/?checkout=" + url.QueryEscape(checkout.ID) + "#account"
	cancelURL := strings.TrimRight(paypalCfg.WebURL, "/") + "/#account"
	application := gin.H{"brand_name": "Vita", "return_url": returnURL, "cancel_url": cancelURL, "user_action": "PAY_NOW"}
	client := paypalClient()
	var providerID, approval string
	if checkout.Kind == "coin" {
		var order paypal.Order
		err = client.Request(c.Request.Context(), "POST", "/v2/checkout/orders", checkout.ID, gin.H{"intent": "CAPTURE", "purchase_units": []gin.H{{"custom_id": checkout.ID, "amount": paypal.Amount{Currency: "USD", Value: paypalValue(checkout.Amount)}}}, "application_context": application}, &order)
		providerID, approval = order.ID, paypal.ApprovalURL(order.Links)
	} else {
		// Verify that the configured plan charges exactly the catalog price, with no trial or setup fee.
		if err = validatePayPalPlan(c.Request.Context(), client, checkout); err == nil {
			application["user_action"] = "SUBSCRIBE_NOW"
			var subscription paypal.Subscription
			err = client.Request(c.Request.Context(), "POST", "/v1/billing/subscriptions", checkout.ID, gin.H{"plan_id": checkout.Plan, "custom_id": checkout.ID, "application_context": application}, &subscription)
			providerID, approval = subscription.ID, paypal.ApprovalURL(subscription.Links)
		}
	}
	if err != nil || providerID == "" || approval == "" {
		c.JSON(502, gin.H{"error": "PayPal checkout creation failed"})
		return
	}
	_, err = db.Get().ExecContext(c.Request.Context(), `UPDATE paypal_checkouts SET provider_id=$2,approval_url=$3,state='approval_pending',updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND (provider_id IS NULL OR provider_id=$2)`, checkout.ID, providerID, approval)
	if err != nil {
		c.JSON(503, gin.H{"error": "failed to save provider checkout; retry with the same request key"})
		return
	}
	c.JSON(200, gin.H{"id": checkout.ID, "url": approval, "status": "approval_pending"})
}
func validatePayPalPlan(ctx context.Context, client paypal.Client, checkout paypalCheckout) error {
	var plan struct {
		Status string `json:"status"`
		Cycles []struct {
			Tenure    string `json:"tenure_type"`
			Total     int    `json:"total_cycles"`
			Frequency struct {
				Unit  string `json:"interval_unit"`
				Count int    `json:"interval_count"`
			} `json:"frequency"`
			Pricing struct {
				Fixed paypal.Amount `json:"fixed_price"`
			} `json:"pricing_scheme"`
		} `json:"billing_cycles"`
		Preferences struct {
			Setup paypal.Amount `json:"setup_fee"`
		} `json:"payment_preferences"`
	}
	if err := client.Request(ctx, "GET", "/v1/billing/plans/"+url.PathEscape(checkout.Plan), "", nil, &plan); err != nil {
		return err
	}
	if plan.Status != "ACTIVE" || len(plan.Cycles) != 1 {
		return errors.New("PayPal plan must be active with one regular billing cycle")
	}
	cycle := plan.Cycles[0]
	unit := "MONTH"
	if checkout.Period == "year" {
		unit = "YEAR"
	} else if checkout.Period != "month" {
		return errors.New("unsupported subscription period")
	}
	amount, err := paypalMinor(cycle.Pricing.Fixed.Value)
	if err != nil || amount != checkout.Amount || cycle.Pricing.Fixed.Currency != "USD" || cycle.Tenure != "REGULAR" || cycle.Total != 0 || cycle.Frequency.Unit != unit || cycle.Frequency.Count != 1 {
		return errors.New("PayPal plan does not match catalog")
	}
	if plan.Preferences.Setup.Value != "" && plan.Preferences.Setup.Value != "0.00" {
		return errors.New("PayPal setup fees are not supported")
	}
	return nil
}
func ConfirmPayPalCheckout(c *gin.Context) {
	checkout, err := scanPayPalCheckout(db.Get().QueryRowContext(c.Request.Context(), `SELECT `+paypalCheckoutColumns+` FROM paypal_checkouts WHERE id=$1 AND user_id=$2`, c.Param("id"), c.GetString("user_id")))
	if err != nil {
		c.JSON(404, gin.H{"error": "checkout not found"})
		return
	}
	if checkout.Provider == "" {
		c.JSON(409, gin.H{"error": "checkout has no provider reference"})
		return
	}
	if checkout.Kind == "coin" {
		err = confirmPayPalOrder(c.Request.Context(), checkout)
	} else {
		err = syncPayPalSubscription(c.Request.Context(), checkout)
	}
	if err != nil {
		c.JSON(502, gin.H{"error": "payment is not confirmed; retry after PayPal processing completes"})
		return
	}
	status := "confirmed"
	if checkout.Kind == "subscription" {
		var paid bool
		if err := db.Get().QueryRowContext(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM paypal_payments WHERE checkout_id=$1 AND refunded_minor<amount_minor)`, checkout.ID).Scan(&paid); err != nil {
			c.JSON(503, gin.H{"error": "payment status unavailable"})
			return
		}
		if !paid {
			status = "pending"
		}
	}
	c.JSON(200, gin.H{"status": status})
}
func confirmPayPalOrder(ctx context.Context, checkout paypalCheckout) error {
	client := paypalClient()
	var order paypal.Order
	if err := client.Request(ctx, "GET", "/v2/checkout/orders/"+url.PathEscape(checkout.Provider), "", nil, &order); err != nil {
		return err
	}
	if order.Status == "APPROVED" {
		if err := client.Request(ctx, "POST", "/v2/checkout/orders/"+url.PathEscape(checkout.Provider)+"/capture", checkout.ID+"-capture", gin.H{}, &order); err != nil {
			return err
		}
	}
	if order.ID != checkout.Provider || order.Status != "COMPLETED" || len(order.Units) != 1 || order.Units[0].CustomID != checkout.ID {
		return errors.New("order is not completed")
	}
	if len(order.Units[0].Payments.Captures) != 1 {
		return errors.New("unexpected capture count")
	}
	capture := order.Units[0].Payments.Captures[0]
	amount, err := paypalMinor(capture.Amount.Value)
	if err != nil || capture.Status != "COMPLETED" || capture.Amount.Currency != "USD" || amount != checkout.Amount || capture.ID == "" {
		return errors.New("capture does not match checkout")
	}
	return fulfillPayPalPayment(ctx, checkout, capture.ID, amount, time.Now().UTC(), nil)
}
func getPayPalSubscription(ctx context.Context, checkout paypalCheckout) (paypal.Subscription, error) {
	var sub paypal.Subscription
	err := paypalClient().Request(ctx, "GET", "/v1/billing/subscriptions/"+url.PathEscape(checkout.Provider), "", nil, &sub)
	if err == nil && (sub.ID != checkout.Provider || sub.PlanID != checkout.Plan || sub.CustomID != checkout.ID) {
		err = errors.New("subscription does not match checkout")
	}
	return sub, err
}
func syncPayPalSubscription(ctx context.Context, checkout paypalCheckout) error {
	sub, err := getPayPalSubscription(ctx, checkout)
	if err != nil {
		return err
	}
	if sub.Status == "APPROVAL_PENDING" || sub.Status == "APPROVED" {
		return errors.New("subscription payment pending")
	}
	// Only a completed, independently verified payment grants access. Activation alone never does.
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = updatePayPalSubscription(tx, checkout, sub); err != nil {
		return err
	}
	if sub.Status == "CANCELLED" || sub.Status == "EXPIRED" {
		if _, err = tx.ExecContext(ctx, `UPDATE paypal_checkouts SET state=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, checkout.ID, strings.ToLower(sub.Status)); err != nil {
			return err
		}
	}
	if err = tx.Commit(); err != nil {
		return err
	}
	return refreshPayPalAccess(checkout.User)
}
func updatePayPalSubscription(tx *sql.Tx, checkout paypalCheckout, sub paypal.Subscription) error {
	// Keep already-paid access after cancellation, until the paid period ends.
	status, renew := "active", sub.Status == "ACTIVE"
	if sub.Status == "EXPIRED" || sub.Status == "SUSPENDED" {
		status = "expired"
	}
	if sub.Status != "ACTIVE" && sub.Status != "CANCELLED" && sub.Status != "EXPIRED" && sub.Status != "SUSPENDED" {
		return errors.New("unsupported subscription state")
	}
	_, err := tx.Exec(`UPDATE subscriptions SET status=$3,will_renew=$4,updated_at=CURRENT_TIMESTAMP WHERE provider='paypal' AND provider_ref=$1 AND user_id=$2`, checkout.Provider, checkout.User, status, renew)
	return err
}
func refreshPayPalAccess(user string) error {
	active, err := userHasActiveSubscription(user)
	if err != nil {
		return err
	}
	return syncUserCompanionEntitlement(user, active)
}
func fulfillPayPalPayment(ctx context.Context, checkout paypalCheckout, transaction string, amount int64, paidAt time.Time, sub *paypal.Subscription) error {
	if transaction == "" || amount != checkout.Amount {
		return errors.New("payment amount mismatch")
	}
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	// The checkout lock serializes browser confirmation, webhooks, refunds and retries.
	var lock string
	if err = tx.QueryRowContext(ctx, `SELECT id FROM paypal_checkouts WHERE id=$1 FOR UPDATE`, checkout.ID).Scan(&lock); err != nil {
		return err
	}
	result, err := tx.ExecContext(ctx, `INSERT INTO paypal_payments(transaction_id,checkout_id,amount_minor,paid_at) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING`, transaction, checkout.ID, amount, paidAt)
	if err != nil {
		return err
	}
	inserted, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if inserted == 0 {
		return tx.Commit()
	}
	if checkout.Kind == "subscription" {
		if sub == nil {
			return errors.New("subscription details missing")
		}
		periodEnd := sub.Billing.NextBillingTime
		// Cancelled subscriptions can omit next_billing_time. The plan has a
		// single verified regular cycle, so the paid cycle is still finite.
		if periodEnd.IsZero() || !periodEnd.After(paidAt) {
			months := 1
			if checkout.Period == "year" {
				months = 12
			} else if checkout.Period != "month" {
				return errors.New("invalid subscription period")
			}
			periodEnd = addClampedMonths(paidAt, months)
		}
		status := "active"
		if sub.Status == "SUSPENDED" || sub.Status == "EXPIRED" {
			status = "expired"
		}
		renew := sub.Status == "ACTIVE"
		_, err = tx.ExecContext(ctx, `INSERT INTO subscriptions(id,user_id,provider,provider_ref,product_id,entitlement,entitlement_ids,status,platform,environment,current_period_start,current_period_end,will_renew) VALUES($1,$2,'paypal',$3,$4,$5,jsonb_build_array($5::text),$6,'web',$7,$8,$9,$10) ON CONFLICT(provider,provider_ref) DO UPDATE SET current_period_start=CASE WHEN EXCLUDED.current_period_end>subscriptions.current_period_end THEN EXCLUDED.current_period_start ELSE subscriptions.current_period_start END,current_period_end=GREATEST(subscriptions.current_period_end,EXCLUDED.current_period_end),status=EXCLUDED.status,will_renew=EXCLUDED.will_renew,updated_at=CURRENT_TIMESTAMP`, uuid.New().String(), checkout.User, checkout.Provider, checkout.Product, checkout.Key, status, currentEnvironment(), paidAt, periodEnd, renew)
		if err != nil {
			return err
		}
	}
	kind := "coin_pack"
	grantKind := "purchase"
	if checkout.Kind == "subscription" {
		kind = "subscription"
		grantKind = "grant"
	}
	if _, err = grantCreditsInTx(tx, checkout.User, checkout.Coins, grantKind, "paypal-payment:"+transaction, "web", true); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO billing_purchases(id,user_id,transaction_id,kind,provider,platform,environment,product_id,amount_minor,currency,credits,status,purchased_at) VALUES($1,$2,$3,$4,'paypal','web',$5,$6,$7,'USD',$8,'paid',$9) ON CONFLICT(provider,transaction_id) DO NOTHING`, uuid.New().String(), checkout.User, transaction, kind, currentEnvironment(), checkout.Product, amount, checkout.Coins, paidAt)
	if err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `UPDATE paypal_checkouts SET state='completed',updated_at=CURRENT_TIMESTAMP WHERE id=$1`, checkout.ID); err != nil {
		return err
	}
	if err = tx.Commit(); err != nil {
		return err
	}
	return refreshPayPalAccess(checkout.User)
}

type paypalEvent struct {
	ID       string          `json:"id"`
	Type     string          `json:"event_type"`
	Resource json.RawMessage `json:"resource"`
}

func PayPalWebhook(c *gin.Context) {
	if !paypalAvailable() {
		c.JSON(503, gin.H{"error": "PayPal is not configured"})
		return
	}
	raw, err := io.ReadAll(http.MaxBytesReader(c.Writer, c.Request.Body, 1<<20))
	var event paypalEvent
	if err != nil || json.Unmarshal(raw, &event) != nil || event.ID == "" {
		c.JSON(400, gin.H{"error": "invalid webhook"})
		return
	}
	verification := gin.H{"auth_algo": c.GetHeader("PAYPAL-AUTH-ALGO"), "cert_url": c.GetHeader("PAYPAL-CERT-URL"), "transmission_id": c.GetHeader("PAYPAL-TRANSMISSION-ID"), "transmission_sig": c.GetHeader("PAYPAL-TRANSMISSION-SIG"), "transmission_time": c.GetHeader("PAYPAL-TRANSMISSION-TIME"), "webhook_id": paypalCfg.WebhookID, "webhook_event": json.RawMessage(raw)}
	var verified struct {
		Status string `json:"verification_status"`
	}
	if err = paypalClient().Request(c.Request.Context(), "POST", "/v1/notifications/verify-webhook-signature", "", verification, &verified); err != nil {
		c.JSON(503, gin.H{"error": "signature verification unavailable"})
		return
	}
	if verified.Status != "SUCCESS" {
		c.JSON(401, gin.H{"error": "invalid webhook signature"})
		return
	}
	var processed bool
	if err = db.Get().QueryRowContext(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM paypal_webhook_events WHERE id=$1)`, event.ID).Scan(&processed); err != nil {
		c.JSON(503, gin.H{"error": "webhook storage unavailable"})
		return
	}
	if processed {
		c.JSON(200, gin.H{"received": true})
		return
	}
	if err = processPayPalEvent(c.Request.Context(), event); err != nil {
		c.JSON(503, gin.H{"error": "fulfillment pending; retry webhook"})
		return
	}
	if _, err = db.Get().ExecContext(c.Request.Context(), `INSERT INTO paypal_webhook_events(id,event_type) VALUES($1,$2) ON CONFLICT DO NOTHING`, event.ID, event.Type); err != nil {
		c.JSON(503, gin.H{"error": "failed to save webhook receipt"})
		return
	}
	c.JSON(200, gin.H{"received": true})
}
func processPayPalEvent(ctx context.Context, event paypalEvent) error {
	var resource struct {
		ID         string    `json:"id"`
		Agreement  string    `json:"billing_agreement_id"`
		CustomID   string    `json:"custom_id"`
		State      string    `json:"state"`
		CreateTime time.Time `json:"create_time"`
		Amount     struct {
			Total    string `json:"total"`
			Value    string `json:"value"`
			Currency string `json:"currency"`
			Code     string `json:"currency_code"`
		} `json:"amount"`
		Supplementary struct {
			Related struct {
				Order   string `json:"order_id"`
				Capture string `json:"capture_id"`
			} `json:"related_ids"`
		} `json:"supplementary_data"`
		Links []paypal.Link `json:"links"`
	}
	if err := json.Unmarshal(event.Resource, &resource); err != nil {
		return err
	}
	provider := ""
	switch event.Type {
	case "CHECKOUT.ORDER.APPROVED":
		provider = resource.ID
	case "PAYMENT.CAPTURE.COMPLETED":
		provider = resource.Supplementary.Related.Order
	case "PAYMENT.SALE.COMPLETED":
		provider = resource.Agreement
	case "BILLING.SUBSCRIPTION.ACTIVATED", "BILLING.SUBSCRIPTION.CANCELLED", "BILLING.SUBSCRIPTION.SUSPENDED", "BILLING.SUBSCRIPTION.EXPIRED", "BILLING.SUBSCRIPTION.UPDATED":
		provider = resource.ID
	case "PAYMENT.CAPTURE.REFUNDED", "PAYMENT.SALE.REFUNDED", "PAYMENT.SALE.REVERSED", "PAYMENT.CAPTURE.REVERSED":
		return refundPayPalEvent(ctx, event.Type, event.Resource)
	default:
		return nil
	}
	if provider == "" {
		return errors.New("webhook has no provider reference")
	}
	checkout, err := scanPayPalCheckout(db.Get().QueryRowContext(ctx, `SELECT `+paypalCheckoutColumns+` FROM paypal_checkouts WHERE provider_id=$1`, provider))
	if errors.Is(err, sql.ErrNoRows) {
		return errors.New("checkout binding is pending")
	}
	if err != nil {
		return err
	}
	if checkout.Kind == "coin" {
		return confirmPayPalOrder(ctx, checkout)
	}
	if event.Type != "PAYMENT.SALE.COMPLETED" {
		return syncPayPalSubscription(ctx, checkout)
	}
	sub, err := getPayPalSubscription(ctx, checkout)
	if err != nil {
		return err
	}
	amount, err := paypalMinor(resource.Amount.Total)
	if err != nil || resource.Amount.Currency != "USD" || resource.State != "completed" || resource.CreateTime.IsZero() {
		return errors.New("invalid subscription payment")
	}
	return fulfillPayPalPayment(ctx, checkout, resource.ID, amount, resource.CreateTime, &sub)
}
func CancelPayPalSubscription(c *gin.Context) {
	var provider string
	err := db.Get().QueryRowContext(c.Request.Context(), `SELECT provider_ref FROM subscriptions WHERE id=$1 AND user_id=$2 AND provider='paypal'`, c.Param("id"), c.GetString("user_id")).Scan(&provider)
	if err != nil {
		c.JSON(404, gin.H{"error": "subscription not found"})
		return
	}
	checkout, err := scanPayPalCheckout(db.Get().QueryRowContext(c.Request.Context(), `SELECT `+paypalCheckoutColumns+` FROM paypal_checkouts WHERE provider_id=$1 AND user_id=$2`, provider, c.GetString("user_id")))
	if err != nil {
		c.JSON(404, gin.H{"error": "subscription checkout unavailable"})
		return
	}
	sub, err := getPayPalSubscription(c.Request.Context(), checkout)
	if err == nil && sub.Status != "CANCELLED" {
		err = paypalClient().Request(c.Request.Context(), "POST", "/v1/billing/subscriptions/"+url.PathEscape(provider)+"/cancel", checkout.ID+"-cancel", gin.H{"reason": "Customer requested cancellation"}, nil)
	}
	if err != nil {
		c.JSON(502, gin.H{"error": "PayPal cancellation failed"})
		return
	}
	if err = syncPayPalSubscription(c.Request.Context(), checkout); err != nil {
		c.JSON(503, gin.H{"error": "cancellation pending synchronization"})
		return
	}
	c.JSON(200, gin.H{"status": "cancelled"})
}

// Refunds are verified against PayPal, then debit coins and invitation rewards in
// the same transaction. A stable provider refund ID makes repeated delivery safe.
func refundPayPalEvent(ctx context.Context, eventType string, raw json.RawMessage) error {
	var event struct {
		ID            string        `json:"id"`
		SaleID        string        `json:"sale_id"`
		Links         []paypal.Link `json:"links"`
		Supplementary struct {
			Related struct {
				Capture string `json:"capture_id"`
			} `json:"related_ids"`
		} `json:"supplementary_data"`
	}
	if err := json.Unmarshal(raw, &event); err != nil {
		return err
	}
	if event.ID == "" {
		return errors.New("refund ID missing")
	}
	client := paypalClient()
	transaction := event.SaleID
	amount := int64(0)
	refundID := event.ID
	if eventType == "PAYMENT.CAPTURE.REFUNDED" {
		var refund struct {
			ID     string        `json:"id"`
			Status string        `json:"status"`
			Amount paypal.Amount `json:"amount"`
			Links  []paypal.Link `json:"links"`
		}
		if err := client.Request(ctx, "GET", "/v2/payments/refunds/"+url.PathEscape(event.ID), "", nil, &refund); err != nil {
			return err
		}
		if refund.Status != "COMPLETED" || refund.Amount.Currency != "USD" {
			return errors.New("refund is not completed")
		}
		var err error
		amount, err = paypalMinor(refund.Amount.Value)
		if err != nil {
			return err
		}
		for _, link := range refund.Links {
			u, err := url.Parse(link.Href)
			if err == nil && link.Rel == "up" && strings.HasPrefix(u.Path, "/v2/payments/captures/") {
				transaction = strings.TrimPrefix(u.Path, "/v2/payments/captures/")
			}
		}
	} else if eventType == "PAYMENT.SALE.REFUNDED" {
		var refund struct {
			ID     string `json:"id"`
			SaleID string `json:"sale_id"`
			State  string `json:"state"`
			Amount struct {
				Total    string `json:"total"`
				Currency string `json:"currency"`
			} `json:"amount"`
		}
		if err := client.Request(ctx, "GET", "/v1/payments/refund/"+url.PathEscape(event.ID), "", nil, &refund); err != nil {
			return err
		}
		if refund.State != "completed" || refund.Amount.Currency != "USD" {
			return errors.New("refund is not completed")
		}
		transaction = refund.SaleID
		var err error
		amount, err = paypalMinor(refund.Amount.Total)
		if err != nil {
			return err
		}
	} else {
		transaction = event.ID
		refundID = "reversal:" + event.ID
		if eventType == "PAYMENT.CAPTURE.REVERSED" {
			var capture paypal.Capture
			if err := client.Request(ctx, "GET", "/v2/payments/captures/"+url.PathEscape(transaction), "", nil, &capture); err != nil {
				return err
			}
			if capture.Status != "DECLINED" && capture.Status != "REFUNDED" {
				return errors.New("capture reversal not verified")
			}
		} else {
			var sale struct {
				State string `json:"state"`
			}
			if err := client.Request(ctx, "GET", "/v1/payments/sale/"+url.PathEscape(transaction), "", nil, &sale); err != nil {
				return err
			}
			if sale.State != "reversed" && sale.State != "refunded" {
				return errors.New("sale reversal not verified")
			}
		}
	}
	if transaction == "" {
		return errors.New("refund has no original transaction")
	}
	var checkoutID string
	err := db.Get().QueryRowContext(ctx, `SELECT checkout_id FROM paypal_payments WHERE transaction_id=$1`, transaction).Scan(&checkoutID)
	if errors.Is(err, sql.ErrNoRows) {
		return errors.New("original fulfillment is pending")
	}
	if err != nil {
		return err
	}
	tx, err := db.Get().BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	checkout, err := scanPayPalCheckout(tx.QueryRowContext(ctx, `SELECT `+paypalCheckoutColumns+` FROM paypal_checkouts WHERE id=$1 FOR UPDATE`, checkoutID))
	if err != nil {
		return err
	}
	var original, refunded int64
	var reversed int
	err = tx.QueryRowContext(ctx, `SELECT amount_minor,refunded_minor,reversed_coins FROM paypal_payments WHERE transaction_id=$1 FOR UPDATE`, transaction).Scan(&original, &refunded, &reversed)
	if err != nil {
		return err
	}
	if strings.HasSuffix(eventType, "REVERSED") {
		amount = original - refunded
	}
	if amount <= 0 {
		return tx.Commit()
	}
	result, err := tx.ExecContext(ctx, `INSERT INTO paypal_refunds(id,transaction_id,amount_minor) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`, refundID, transaction, amount)
	if err != nil {
		return err
	}
	count, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return tx.Commit()
	}
	if amount > original-refunded {
		return errors.New("refund exceeds original payment")
	}
	total := refunded + amount
	target := int(int64(checkout.Coins) * total / original)
	debit := target - reversed
	if debit > 0 {
		if _, err = grantCreditsInTx(tx, checkout.User, -debit, "refund", "paypal-refund:"+refundID, "web", false); err != nil {
			return err
		}
	}
	// Reverse only the reward paid for the original purchase; never reward a refund.
	var rewardID, inviter string
	var sourceCoins, rewardCoins int
	err = tx.QueryRowContext(ctx, `SELECT r.source_transaction_id,r.inviter_user_id,r.source_coins,r.reward_coins FROM invitation_rewards r JOIN credit_transactions t ON t.id=r.source_transaction_id WHERE t.user_id=$1 AND t.description=$2`, checkout.User, "paypal-payment:"+transaction).Scan(&rewardID, &inviter, &sourceCoins, &rewardCoins)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if err == nil && sourceCoins > 0 {
		previous := int64(rewardCoins) * int64(reversed) / int64(sourceCoins)
		next := int64(rewardCoins) * int64(target) / int64(sourceCoins)
		if next > previous {
			if _, err = grantCreditsInTx(tx, inviter, -int(next-previous), "refund", "paypal-invitation-refund:"+refundID, "web", false); err != nil {
				return err
			}
		}
	}
	if _, err = tx.ExecContext(ctx, `UPDATE paypal_payments SET refunded_minor=$2,reversed_coins=$3 WHERE transaction_id=$1`, transaction, total, target); err != nil {
		return err
	}
	status := "partially_refunded"
	if total == original {
		status = "refunded"
	}
	if _, err = tx.ExecContext(ctx, `UPDATE billing_purchases SET status=$2 WHERE provider='paypal' AND transaction_id=$1`, transaction, status); err != nil {
		return err
	}
	if total == original && checkout.Kind == "subscription" {
		if _, err = tx.ExecContext(ctx, `UPDATE subscriptions SET status='expired',current_period_end=CURRENT_TIMESTAMP,will_renew=false,updated_at=CURRENT_TIMESTAMP WHERE provider='paypal' AND provider_ref=$1 AND current_period_start <= (SELECT paid_at FROM paypal_payments WHERE transaction_id=$2)`, checkout.Provider, transaction); err != nil {
			return err
		}
	}
	if err = tx.Commit(); err != nil {
		return err
	}
	return refreshPayPalAccess(checkout.User)
}

// Annual memberships receive their configured allowance monthly, matching App
// billing. Each renewal uses a separate transaction and independent grant keys.
func GrantDuePayPalAnnualCredits(ctx context.Context) error {
	rows, err := db.Get().QueryContext(ctx, `SELECT p.transaction_id,c.id,c.user_id,c.coins,p.paid_at,s.current_period_end
 FROM paypal_payments p JOIN paypal_checkouts c ON c.id=p.checkout_id
 JOIN subscriptions s ON s.provider='paypal' AND s.provider_ref=c.provider_id
 WHERE c.kind='subscription' AND c.period='year' AND p.refunded_minor=0
 AND s.status='active' AND s.current_period_end>CURRENT_TIMESTAMP AND s.current_period_start=p.paid_at`)
	if err != nil {
		return err
	}
	type annual struct {
		transaction, checkout, user string
		coins                       int
		start, end                  time.Time
	}
	entries := []annual{}
	for rows.Next() {
		var item annual
		if err := rows.Scan(&item.transaction, &item.checkout, &item.user, &item.coins, &item.start, &item.end); err != nil {
			rows.Close()
			return err
		}
		entries = append(entries, item)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, entry := range entries {
		for _, month := range monthlyInstallmentsDue(entry.start, entry.end, time.Now().UTC()) {
			tx, err := db.Get().BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			var allowed bool
			err = tx.QueryRowContext(ctx, `SELECT p.refunded_minor=0 AND s.status='active' AND s.current_period_end>CURRENT_TIMESTAMP FROM paypal_checkouts c JOIN paypal_payments p ON p.checkout_id=c.id JOIN subscriptions s ON s.provider='paypal' AND s.provider_ref=c.provider_id WHERE c.id=$1 AND p.transaction_id=$2 FOR UPDATE OF c,p`, entry.checkout, entry.transaction).Scan(&allowed)
			if err == nil && allowed {
				_, err = grantCreditsInTx(tx, entry.user, entry.coins, "grant", fmt.Sprintf("paypal-annual:%s:%d", entry.transaction, month), "web", true)
			}
			if err != nil {
				tx.Rollback()
				return err
			}
			if err = tx.Commit(); err != nil {
				return err
			}
		}
	}
	return nil
}

package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"vita/internal/paypal"
)

func TestPayPalMoney(t *testing.T) {
	for _, test := range []struct {
		value string
		minor int64
	}{{"0.01", 1}, {"12.30", 1230}, {"199.99", 19999}} {
		minor, err := paypalMinor(test.value)
		if err != nil || minor != test.minor || paypalValue(minor) != test.value {
			t.Fatalf("incorrect amount %s", test.value)
		}
	}
	for _, value := range []string{"-1.00", "1e2", "1.001", "1", "NaN", "999999999999999999999999.00"} {
		if _, err := paypalMinor(value); err == nil {
			t.Fatalf("accepted invalid amount %q", value)
		}
	}
}
func TestPayPalAvailabilityRequiresSafeConfiguration(t *testing.T) {
	previous := paypalCfg
	defer func() { paypalCfg = previous }()
	valid := PayPalConfig{ClientID: "client", Secret: "secret", WebhookID: "hook", Mode: "sandbox", WebURL: "http://localhost:5176"}
	paypalCfg = valid
	if !paypalAvailable() {
		t.Fatal("Sandbox loopback should work")
	}
	for _, test := range []struct{ mode, url string }{{"live", "http://localhost:5176"}, {"sandbox", "http://example.com"}, {"unknown", "https://example.com"}, {"sandbox", "javascript:alert(1)"}} {
		paypalCfg = valid
		paypalCfg.Mode = test.mode
		paypalCfg.WebURL = test.url
		if paypalAvailable() {
			t.Fatalf("unsafe configuration accepted: %v", test)
		}
	}
}
func TestPayPalPlanRejectsPriceTrialsAndSetupFees(t *testing.T) {
	for _, test := range []struct {
		name, price, tenure, setup string
		cycles                     int
		valid                      bool
	}{{"matching", "10.00", "REGULAR", "0.00", 1, true}, {"different price", "9.00", "REGULAR", "0.00", 1, false}, {"trial", "10.00", "TRIAL", "0.00", 1, false}, {"extra cycles", "10.00", "REGULAR", "0.00", 2, false}, {"setup charge", "10.00", "REGULAR", "1.00", 1, false}} {
		t.Run(test.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/v1/oauth2/token" {
					json.NewEncoder(w).Encode(map[string]string{"access_token": "token"})
					return
				}
				cycles := []any{}
				for i := 0; i < test.cycles; i++ {
					cycles = append(cycles, map[string]any{"tenure_type": test.tenure, "total_cycles": 0, "frequency": map[string]any{"interval_unit": "MONTH", "interval_count": 1}, "pricing_scheme": map[string]any{"fixed_price": paypal.Amount{Value: test.price, Currency: "USD"}}})
				}
				json.NewEncoder(w).Encode(map[string]any{"status": "ACTIVE", "billing_cycles": cycles, "payment_preferences": map[string]any{"setup_fee": paypal.Amount{Value: test.setup, Currency: "USD"}}})
			}))
			defer server.Close()
			client := paypal.Client{BaseURL: server.URL, HTTP: server.Client()}
			err := validatePayPalPlan(context.Background(), client, paypalCheckout{Plan: "P-1", Period: "month", Amount: 1000})
			if (err == nil) != test.valid {
				t.Fatalf("plan validation mismatch: %v", err)
			}
		})
	}
}

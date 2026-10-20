package paypal

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRequestUsesServerCredentialsAndIdempotency(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		switch r.URL.Path {
		case "/v1/oauth2/token":
			user, secret, ok := r.BasicAuth()
			if !ok || user != "client" || secret != "secret" {
				t.Error("missing server credentials")
			}
			_ = r.ParseForm()
			if r.Form.Get("grant_type") != "client_credentials" {
				t.Error("incorrect OAuth grant")
			}
			json.NewEncoder(w).Encode(map[string]string{"access_token": "access"})
		case "/v2/checkout/orders":
			if r.Header.Get("Authorization") != "Bearer access" || r.Header.Get("PayPal-Request-Id") != "request-1" {
				t.Error("missing authorization or deduplication key")
			}
			json.NewEncoder(w).Encode(map[string]string{"id": "order"})
		default:
			t.Error("unexpected endpoint")
			w.WriteHeader(404)
		}
	}))
	defer server.Close()
	client := Client{ClientID: "client", Secret: "secret", BaseURL: server.URL, HTTP: server.Client()}
	var order Order
	if err := client.Request(context.Background(), "POST", "/v2/checkout/orders", "request-1", map[string]string{"intent": "CAPTURE"}, &order); err != nil {
		t.Fatal(err)
	}
	if order.ID != "order" || calls != 2 {
		t.Fatal("incorrect provider result")
	}
}
func TestRequestRejectsProviderErrors(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(401)
		w.Write([]byte(`{"secret":"must not leak"}`))
	}))
	defer server.Close()
	client := Client{BaseURL: server.URL, HTTP: server.Client()}
	if err := client.Request(context.Background(), "GET", "/order", "", nil, nil); err == nil || err.Error() != "paypal authorization failed (401)" {
		t.Fatal("provider errors must not expose response bodies")
	}
}
func TestApprovalURLRestrictsDestinations(t *testing.T) {
	for _, value := range []string{"javascript:alert(1)", "https://www.paypal.com.evil.test/pay", "https://www.paypal.com@evil.test/pay", "http://www.paypal.com/pay", "https://www.paypal.com:443/pay"} {
		if ApprovalURL([]Link{{Rel: "approve", Href: value}}) != "" {
			t.Fatalf("unsafe approval URL accepted: %s", value)
		}
	}
	valid := "https://www.sandbox.paypal.com/checkoutnow?token=123"
	if ApprovalURL([]Link{{Rel: "approve", Href: valid}}) != valid {
		t.Fatal("valid Sandbox approval URL rejected")
	}
}

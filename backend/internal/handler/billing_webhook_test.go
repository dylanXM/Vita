package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRevenueCatWebhookFailsClosedWithoutSecret(t *testing.T) {
	previous := billingCfg
	billingCfg.RevenueCatWebhookSecret = ""
	t.Cleanup(func() { billingCfg = previous })

	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPost, "/v1/webhooks/revenuecat", strings.NewReader(`{"event":{}}`))
	RevenueCatWebhook(c)
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d; want %d", recorder.Code, http.StatusServiceUnavailable)
	}
}

func TestStripeWebhookFailsClosedWithoutSecret(t *testing.T) {
	previous := billingCfg
	billingCfg.StripeWebhookSecret = ""
	t.Cleanup(func() { billingCfg = previous })

	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPost, "/v1/webhooks/stripe", strings.NewReader(`{}`))
	StripeWebhook(c)
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d; want %d", recorder.Code, http.StatusServiceUnavailable)
	}
}

func TestRevenueCatWebhookRejectsInvalidSecret(t *testing.T) {
	previous := billingCfg
	billingCfg.RevenueCatWebhookSecret = "correct-secret"
	t.Cleanup(func() { billingCfg = previous })
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest(http.MethodPost, "/v1/webhooks/revenuecat", strings.NewReader(`{"event":{"type":"TEST"}}`))
	c.Request.Header.Set("Authorization", "Bearer wrong-secret")
	RevenueCatWebhook(c)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d", recorder.Code)
	}
}

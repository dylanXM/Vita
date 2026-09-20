package handler

import (
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestAdminBillingEnvironmentDefaultsToDeployment(t *testing.T) {
	previous := envName
	envName = "beta"
	t.Cleanup(func() { envName = previous })

	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest("GET", "/v1/admin/subscription-plans", nil)
	environment, ok := adminBillingEnvironment(c)
	if !ok || environment != "beta" {
		t.Fatalf("environment = %q, ok = %v; want beta, true", environment, ok)
	}
}

func TestPlatformFromRevenueCatStore(t *testing.T) {
	tests := map[string]string{
		"APP_STORE":  "ios",
		"PLAY_STORE": "android",
		"STRIPE":     "web",
		"unknown":    "system",
	}
	for store, want := range tests {
		if got := platformFromRevenueCatStore(store); got != want {
			t.Errorf("platformFromRevenueCatStore(%q) = %q; want %q", store, got, want)
		}
	}
}

func TestCreditsFromProductIDSupportsVitaCatalog(t *testing.T) {
	tests := map[string]int{
		"vita.coins.100":    100,
		"vita.coins.500":    500,
		"vita.coins.1200":   1200,
		"coins_500":         500,
		"vita.plus.monthly": 0,
	}
	for productID, want := range tests {
		if got := creditsFromProductID(productID); got != want {
			t.Errorf("creditsFromProductID(%q) = %d; want %d", productID, got, want)
		}
	}
}

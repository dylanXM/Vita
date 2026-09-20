package handler

import (
	"net/http/httptest"
	"testing"
	"time"

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

func TestMonthlyInstallmentsDueUsesAnchoredClampedDates(t *testing.T) {
	start := time.Date(2026, time.January, 31, 10, 0, 0, 0, time.UTC)
	end := time.Date(2027, time.January, 31, 10, 0, 0, 0, time.UTC)
	beforeFirstDue := time.Date(2026, time.February, 28, 9, 59, 0, 0, time.UTC)
	if got := monthlyInstallmentsDue(start, end, beforeFirstDue); len(got) != 0 {
		t.Fatalf("installments before first due = %#v", got)
	}
	afterMarchDue := time.Date(2026, time.March, 31, 10, 0, 0, 0, time.UTC)
	got := monthlyInstallmentsDue(start, end, afterMarchDue)
	if len(got) != 2 || got[0] != 1 || got[1] != 2 {
		t.Fatalf("installments = %#v; want [1 2]", got)
	}
}

func TestMonthlyInstallmentsDueNeverIncludesAnnualRenewal(t *testing.T) {
	start := time.Date(2026, time.September, 20, 0, 0, 0, 0, time.UTC)
	end := start.AddDate(1, 0, 0)
	got := monthlyInstallmentsDue(start, end, end)
	if len(got) != 11 || got[10] != 11 {
		t.Fatalf("installments = %#v; want 1 through 11", got)
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

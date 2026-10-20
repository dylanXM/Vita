package handler

import "testing"

func TestAnalyticsEventValidation(t *testing.T) {
	for _, name := range []string{"screen_view", "message_sent", "purchase.succeeded"} {
		if !validAnalyticsName(name) {
			t.Fatalf("expected %q to be valid", name)
		}
	}
	for _, name := range []string{"", "A", "Screen View", "事件"} {
		if validAnalyticsName(name) {
			t.Fatalf("expected %q to be invalid", name)
		}
	}
}

func TestAnalyticsCategoryNormalization(t *testing.T) {
	tests := map[string]string{
		"screen_view":          "navigation",
		"auth_login_started":   "auth",
		"message_sent":         "chat",
		"purchase_started":     "billing",
		"whats_new_impression": "updates",
	}
	for name, want := range tests {
		if got := normalizeAnalyticsCategory("", name); got != want {
			t.Fatalf("category(%q) = %q, want %q", name, got, want)
		}
	}
	if got := normalizeAnalyticsCategory("life", "custom_action"); got != "life" {
		t.Fatalf("explicit category = %q", got)
	}
}

func TestAnonymousAnalyticsAllowlist(t *testing.T) {
	if !anonymousAnalyticsAllowed("onboarding_viewed") || !anonymousAnalyticsAllowed("auth_login_started") {
		t.Fatal("expected onboarding and auth events to be accepted anonymously")
	}
	if anonymousAnalyticsAllowed("message_sent") {
		t.Fatal("authenticated behavior must not be accepted anonymously")
	}
}

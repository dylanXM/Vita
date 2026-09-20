package handler

import "testing"

func TestVersionAtLeast(t *testing.T) {
	tests := []struct {
		current string
		minimum string
		want    bool
	}{
		{"1.0.0", "1.0.0", true},
		{"1.2.0", "1.1.9", true},
		{"1.0.0", "1.0.1", false},
		{"", "1.0.0", false},
		{"1.0.0", "", true},
	}
	for _, test := range tests {
		if got := versionAtLeast(test.current, test.minimum); got != test.want {
			t.Fatalf("versionAtLeast(%q, %q) = %v, want %v", test.current, test.minimum, got, test.want)
		}
	}
}

func TestContentActionValidation(t *testing.T) {
	for _, action := range []string{"", "next", "close", "route", "url"} {
		if !validCTAAction(action) {
			t.Fatalf("expected %q to be valid", action)
		}
	}
	if validCTAAction("script") {
		t.Fatal("unexpected custom action accepted")
	}
}

func TestNormalizeExternalURL(t *testing.T) {
	tests := []struct {
		value string
		want  string
		ok    bool
	}{
		{"", "", true},
		{"  https://www.instagram.com/vita  ", "https://www.instagram.com/vita", true},
		{"http://x.com/vita", "http://x.com/vita", true},
		{"mailto:hello@example.com", "", false},
		{"javascript:alert(1)", "", false},
		{"https:///missing-host", "", false},
	}
	for _, test := range tests {
		got, ok := normalizeExternalURL(test.value)
		if got != test.want || ok != test.ok {
			t.Errorf("normalizeExternalURL(%q) = (%q, %v), want (%q, %v)", test.value, got, ok, test.want, test.ok)
		}
	}
}

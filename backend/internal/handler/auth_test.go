package handler

import (
	"regexp"
	"testing"
)

func TestGenerateCodeAlwaysReturnsSixDigits(t *testing.T) {
	pattern := regexp.MustCompile(`^[0-9]{6}$`)
	for i := 0; i < 1000; i++ {
		code, err := generateCode()
		if err != nil {
			t.Fatal(err)
		}
		if !pattern.MatchString(code) {
			t.Fatalf("generated invalid verification code %q", code)
		}
	}
}

func TestVerificationCodeKeyNormalizesEmail(t *testing.T) {
	if got := verificationCodeKey(" User@Example.COM ", "012345"); got != "vcode:user@example.com:012345" {
		t.Fatalf("verificationCodeKey() = %q", got)
	}
}

func TestRegistrationLegalAcceptance(t *testing.T) {
	accepted := true
	acceptedAt, err := registrationLegalAcceptance(&accepted)
	if err != nil || acceptedAt == nil {
		t.Fatalf("accepted consent = %v, %v; want timestamp and no error", acceptedAt, err)
	}

	rejected := false
	if acceptedAt, err := registrationLegalAcceptance(&rejected); err == nil || acceptedAt != nil {
		t.Fatalf("rejected consent = %v, %v; want nil timestamp and error", acceptedAt, err)
	}

	if acceptedAt, err := registrationLegalAcceptance(nil); err == nil || acceptedAt != nil {
		t.Fatalf("omitted consent = %v, %v; want nil timestamp and error", acceptedAt, err)
	}
}

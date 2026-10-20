package mail

import (
	"strings"
	"testing"
)

func TestWriteMessageContainsParts(t *testing.T) {
	var b strings.Builder
	if err := writeMessage(&b, "Vita <noreply@vita.app>", "user@example.com", "123456"); err != nil {
		t.Fatal(err)
	}
	out := b.String()
	for _, want := range []string{
		"From: Vita <noreply@vita.app>",
		"To: user@example.com",
		"Content-Type: multipart/alternative; boundary=\"alt-0\"",
		"Subject: Your Vita verification code",
		"123456",
		"Content-Transfer-Encoding: quoted-printable",
		"--alt-0--",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in message", want)
		}
	}
}

func TestZeroConfigFallsBackToLog(t *testing.T) {
	c := &Config{}
	if c.Enabled() {
		t.Fatal("zero config must be disabled")
	}
	if err := c.SendVerificationCode("user@example.com", "123456"); err != nil {
		t.Fatalf("dev fallback should not error: %v", err)
	}
}

package agent

import "testing"

func TestSecretBoxRoundTrip(t *testing.T) {
	box, err := NewSecretBox("test-key")
	if err != nil {
		t.Fatal(err)
	}
	encoded, err := box.Encrypt("secret-value")
	if err != nil {
		t.Fatal(err)
	}
	if encoded == "secret-value" {
		t.Fatal("secret was not encrypted")
	}
	plain, err := box.Decrypt(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if plain != "secret-value" {
		t.Fatalf("got %q", plain)
	}
}

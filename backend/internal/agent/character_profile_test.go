package agent

import "testing"

func TestParseCharacterProfileNormalizesTags(t *testing.T) {
	profile, err := parseCharacterProfile("```json\n{\"name\":\" Mina \",\"personality_tags\":[\"Warm\",\" warm \",\"Witty\"]}\n```")
	if err != nil {
		t.Fatal(err)
	}
	if profile.Name != "Mina" || len(profile.PersonalityTags) != 2 || profile.PersonalityTags[0] != "warm" {
		t.Fatalf("unexpected profile: %#v", profile)
	}
}

func TestParseCharacterProfileRequiresName(t *testing.T) {
	if _, err := parseCharacterProfile(`{"name":""}`); err == nil {
		t.Fatal("expected missing name to fail")
	}
}

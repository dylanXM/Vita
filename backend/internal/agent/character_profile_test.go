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

func TestParseCharacterProfileAcceptsStringLists(t *testing.T) {
	profile, err := parseCharacterProfile(`{"name":"Mina","interests":["urban ecology","hiking"],"likes":["tea","gardens"],"personality_tags":"Thoughtful"}`)
	if err != nil {
		t.Fatal(err)
	}
	if profile.Interests != "urban ecology, hiking" || profile.Likes != "tea, gardens" || len(profile.PersonalityTags) != 1 || profile.PersonalityTags[0] != "thoughtful" {
		t.Fatalf("unexpected profile: %#v", profile)
	}
}

func TestParseCharacterProfileRejectsNonStringList(t *testing.T) {
	if _, err := parseCharacterProfile(`{"name":"Mina","interests":["hiking",3]}`); err == nil {
		t.Fatal("expected invalid interest list to fail")
	}
}

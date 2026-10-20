package companion

import "testing"

func TestRelationshipCatalogStages(t *testing.T) {
	for _, role := range []string{"girlfriend", "boyfriend", "wife", "husband", "crush", "confidant", "family", "mentor", "colleague", "friend", "custom"} {
		option, ok := Relationship(role)
		if !ok {
			t.Fatalf("missing %s", role)
		}
		if err := ValidateRelationship(role, option.DefaultStage); err != nil {
			t.Fatal(err)
		}
	}
	for _, role := range []string{"crush", "confidant", "family", "mentor", "colleague", "friend"} {
		if ValidateRelationship(role, "partner") == nil {
			t.Fatalf("non-romantic role %s accepts partner", role)
		}
	}
	for _, tc := range []struct{ role, stage, gender, wantRole, wantStage string }{
		{"wife", "partner", "male", "husband", "partner"},
		{"husband", "partner", "female", "wife", "partner"},
		{"friend", "partner", "", "friend", "acquaintance"},
		{"family", "", "", "family", "close"},
		{"custom", "close", "", "custom", "close"},
	} {
		role, stage, err := NormalizeRelationship(tc.role, tc.stage, tc.gender)
		if err != nil || role != tc.wantRole || stage != tc.wantStage {
			t.Fatalf("%+v: %s %s %v", tc, role, stage, err)
		}
	}
	if _, _, err := NormalizeRelationship("unknown", "close", ""); err == nil {
		t.Fatal("unknown role accepted")
	}
}

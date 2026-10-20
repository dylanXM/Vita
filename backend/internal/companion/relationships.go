package companion

import (
	"errors"
	"fmt"
)

var ErrInvalidRelationship = errors.New("invalid relationship")

type RelationshipOption struct {
	Key          string   `json:"key"`
	GenderHint   string   `json:"gender_hint"`
	PairedRole   string   `json:"paired_role,omitempty"`
	Stages       []string `json:"stages"`
	DefaultStage string   `json:"default_stage"`
}

func RelationshipOptions() []RelationshipOption {
	return []RelationshipOption{
		{"girlfriend", "female", "boyfriend", []string{"partner"}, "partner"},
		{"boyfriend", "male", "girlfriend", []string{"partner"}, "partner"},
		{"wife", "female", "husband", []string{"partner"}, "partner"},
		{"husband", "male", "wife", []string{"partner"}, "partner"},
		{"crush", "", "", []string{"stranger", "acquaintance", "close"}, "acquaintance"},
		{"confidant", "", "", []string{"acquaintance", "close"}, "close"},
		{"family", "", "", []string{"acquaintance", "close"}, "close"},
		{"mentor", "", "", []string{"stranger", "acquaintance", "close"}, "acquaintance"},
		{"colleague", "", "", []string{"stranger", "acquaintance", "close"}, "acquaintance"},
		{"friend", "", "", []string{"acquaintance", "close"}, "acquaintance"},
		{"custom", "", "", []string{"stranger", "acquaintance", "close", "partner"}, "stranger"},
	}
}

func Relationship(role string) (RelationshipOption, bool) {
	for _, option := range RelationshipOptions() {
		if option.Key == role {
			return option, true
		}
	}
	return RelationshipOption{}, false
}

func ValidateRelationship(role, stage string) error {
	option, ok := Relationship(role)
	if !ok {
		return fmt.Errorf("%w: unknown relationship type", ErrInvalidRelationship)
	}
	for _, allowed := range option.Stages {
		if stage == allowed {
			return nil
		}
	}
	return fmt.Errorf("%w: relationship stage is not available for this relationship type", ErrInvalidRelationship)
}

func NormalizeRelationship(role, stage, gender string) (string, string, error) {
	option, ok := Relationship(role)
	if !ok {
		return "", "", fmt.Errorf("%w: unknown relationship type", ErrInvalidRelationship)
	}
	if option.GenderHint != "" && (gender == "male" || gender == "female") && option.GenderHint != gender {
		role = option.PairedRole
		option, _ = Relationship(role)
	}
	if stage == "" {
		stage = option.DefaultStage
	} else if stage != "stranger" && stage != "acquaintance" && stage != "close" && stage != "partner" {
		return "", "", fmt.Errorf("%w: unknown relationship stage", ErrInvalidRelationship)
	}
	// Legacy form selections such as stranger for girlfriend are normalized to
	// the selected initial relationship, just as creation did before this change.
	if err := ValidateRelationship(role, stage); err != nil {
		stage = option.DefaultStage
	}
	return role, stage, nil
}

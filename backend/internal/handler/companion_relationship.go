package handler

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"vita/internal/companion"
	"vita/internal/db"
)

var errCompanionPortraitUnavailable = errors.New("companion portrait is unavailable")

// Portrait metadata is the source of truth for a template character's
// presentation. Older clients may send an incompatible relationship choice;
// normalize it before persisting instead of creating contradictory profiles.
func alignCompanionRelationship(ctx context.Context, req *CreateCompanionRequest) error {
	genderHint := ""
	if req.Gender == "" {
		req.Gender = "custom"
	}
	if req.PortraitID != nil && strings.TrimSpace(*req.PortraitID) != "" {
		var portraitGender string
		err := db.Get().QueryRowContext(ctx,
			`SELECT gender FROM companion_portraits WHERE id=$1`,
			strings.TrimSpace(*req.PortraitID)).Scan(&portraitGender)
		if errors.Is(err, sql.ErrNoRows) {
			return errCompanionPortraitUnavailable
		}
		if err != nil {
			return err
		}
		switch strings.ToLower(strings.TrimSpace(portraitGender)) {
		case "boyfriend", "husband", "male", "man", "boy":
			genderHint = "male"
		case "girlfriend", "wife", "female", "woman", "girl":
			genderHint = "female"
		}
	}
	role, stage, err := companion.NormalizeRelationship(req.Gender, req.RelationshipStage, genderHint)
	if err != nil {
		return err
	}
	req.Gender, req.RelationshipStage = role, stage
	return nil
}

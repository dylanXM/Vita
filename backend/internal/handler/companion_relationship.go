package handler

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"vita/internal/db"
)

var errCompanionPortraitUnavailable = errors.New("companion portrait is unavailable")

// Portrait metadata is the source of truth for a template character's
// presentation. Older clients may send an incompatible relationship choice;
// normalize it before persisting instead of creating contradictory profiles.
func alignCompanionRelationship(ctx context.Context, req *CreateCompanionRequest) error {
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
		case "boyfriend", "male", "man", "boy":
			if req.Gender == "girlfriend" {
				req.Gender = "boyfriend"
			}
		case "girlfriend", "female", "woman", "girl":
			if req.Gender == "boyfriend" {
				req.Gender = "girlfriend"
			}
		}
	}
	if req.RelationshipStage == "" {
		req.RelationshipStage = "stranger"
	}
	switch req.Gender {
	case "girlfriend", "boyfriend":
		req.RelationshipStage = "partner"
	case "friend":
		switch req.RelationshipStage {
		case "stranger":
			req.RelationshipStage = "acquaintance"
		case "partner":
			req.RelationshipStage = "close"
		}
	}
	return nil
}

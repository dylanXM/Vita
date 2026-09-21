package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// CharacterProfile is an editable companion draft generated from user-provided
// source material. The app must present it for confirmation before creation.
type CharacterProfile struct {
	Name            string   `json:"name"`
	Gender          string   `json:"gender"`
	Persona         string   `json:"persona"`
	Appearance      string   `json:"appearance"`
	City            string   `json:"city"`
	Occupation      string   `json:"occupation"`
	Interests       string   `json:"interests"`
	PersonalityTags []string `json:"personality_tags"`
	SpeakingStyle   string   `json:"speaking_style"`
	Likes           string   `json:"likes"`
	Dislikes        string   `json:"dislikes"`
	LifeHabits      string   `json:"life_habits"`
	LifeGoal        string   `json:"life_goal"`
	Backstory       string   `json:"backstory"`
}

func (s *Service) GenerateCharacterProfile(ctx context.Context, userID, mode, source, characterName string) (CharacterProfile, error) {
	if s.mock {
		name := strings.TrimSpace(characterName)
		if name == "" {
			name = "Nova"
		}
		return CharacterProfile{Name: name, Gender: "custom", Persona: strings.TrimSpace(source), PersonalityTags: []string{"thoughtful"}}, nil
	}
	models, err := s.loadTextRouteModels(ctx, "text_character_profile", "", userID)
	if err != nil {
		return CharacterProfile{}, err
	}
	task := "Create one original fictional character from the user's description."
	if mode == "meet_file" {
		task = fmt.Sprintf("Distill only the character named %q from the uploaded source. Do not merge traits from other people.", characterName)
	}
	prompt := fmt.Sprintf(`%s

Return one strict JSON object with exactly these fields: name, gender, persona, appearance, city, occupation, interests, personality_tags, speaking_style, likes, dislikes, life_habits, life_goal, backstory.
personality_tags must contain 1 to 8 short lowercase English tags. Use an empty string when the source does not establish a field. Do not invent sensitive personal facts, contact details, or claims about a real person's private life. The result must be suitable for an explicitly AI character.

Source:
%s`, task, source)
	output, _, err := s.generateTextWithFallback(ctx, "", "character_profile", models, GenerateRequest{
		System:      "You turn user-provided material into a grounded, editable AI character profile. Output strict JSON only.",
		Messages:    []ChatMessage{{Role: "user", Content: prompt}},
		Temperature: 0.4,
		MaxTokens:   1400,
	})
	if err != nil {
		return CharacterProfile{}, err
	}
	return parseCharacterProfile(output)
}

func parseCharacterProfile(output string) (CharacterProfile, error) {
	clean := strings.TrimSpace(output)
	if strings.HasPrefix(clean, "```") {
		clean = strings.TrimPrefix(clean, "```json")
		clean = strings.TrimPrefix(clean, "```")
		clean = strings.TrimSuffix(strings.TrimSpace(clean), "```")
	}
	var profile CharacterProfile
	if err := json.Unmarshal([]byte(clean), &profile); err != nil {
		return CharacterProfile{}, fmt.Errorf("decode character profile: %w", err)
	}
	profile.Name = strings.TrimSpace(profile.Name)
	if profile.Name == "" {
		return CharacterProfile{}, fmt.Errorf("generated character profile has no name")
	}
	seen := map[string]bool{}
	tags := make([]string, 0, len(profile.PersonalityTags))
	for _, tag := range profile.PersonalityTags {
		tag = strings.ToLower(strings.TrimSpace(tag))
		if tag != "" && !seen[tag] && len(tags) < 8 {
			seen[tag] = true
			tags = append(tags, tag)
		}
	}
	profile.PersonalityTags = tags
	return profile, nil
}

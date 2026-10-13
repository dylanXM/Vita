package agent

import (
	"encoding/json"
	"fmt"
	"strings"
	"unicode/utf8"
)

type momentSceneAction struct {
	Label   string `json:"label"`
	Message string `json:"message"`
}

// Scene choices are suggestions only. Nothing is sent or purchased until the
// user selects one, and the normal message endpoint validates the resulting text.
type momentExperienceProposal struct {
	Title     string `json:"title"`
	Challenge string `json:"challenge"`
	Decision  string `json:"decision"`
	Note      string `json:"note"`
}

type momentScene struct {
	Reply     string                    `json:"reply"`
	Actions   []momentSceneAction       `json:"actions"`
	Situation string                    `json:"situation"`
	Focus     string                    `json:"focus"`
	Goal      string                    `json:"goal"`
	Challenge string                    `json:"challenge"`
	Proposal  *momentExperienceProposal `json:"proposal"`
}

func decodeMomentScene(raw string) (string, []momentSceneAction, error) {
	scene, err := decodeMomentSceneState(raw)
	return scene.Reply, scene.Actions, err
}

func decodeMomentSceneState(raw string) (momentScene, error) {
	text := strings.TrimSpace(raw)
	if strings.HasPrefix(text, "```") {
		if newline := strings.IndexByte(text, '\n'); newline >= 0 {
			text = strings.TrimSpace(strings.TrimSuffix(text[newline+1:], "```"))
		}
	}
	if !strings.HasPrefix(text, "{") {
		return momentScene{Reply: text}, nil
	}
	var scene momentScene
	if err := json.Unmarshal([]byte(text), &scene); err != nil || strings.TrimSpace(scene.Reply) == "" {
		return momentScene{}, fmt.Errorf("shared scene returned an invalid reply")
	}
	actions := make([]momentSceneAction, 0, 2)
	for _, action := range scene.Actions {
		action.Label = strings.TrimSpace(action.Label)
		action.Message = strings.TrimSpace(action.Message)
		if action.Label == "" || action.Message == "" || utf8.RuneCountInString(action.Label) > 60 || utf8.RuneCountInString(action.Message) > 300 || requestsPaidMedia(action.Message) {
			continue
		}
		actions = append(actions, action)
		if len(actions) == 2 {
			break
		}
	}
	scene.Goal = truncate(strings.TrimSpace(scene.Goal), 160)
	scene.Challenge = truncate(strings.TrimSpace(scene.Challenge), 240)
	if scene.Proposal != nil {
		p := scene.Proposal
		p.Title = strings.TrimSpace(p.Title)
		p.Challenge = strings.TrimSpace(p.Challenge)
		p.Decision = strings.TrimSpace(p.Decision)
		p.Note = strings.TrimSpace(p.Note)
		if p.Title == "" || p.Challenge == "" || p.Decision == "" || p.Note == "" || utf8.RuneCountInString(p.Title) > 80 || utf8.RuneCountInString(p.Challenge) > 240 || utf8.RuneCountInString(p.Decision) > 500 || utf8.RuneCountInString(p.Note) > 500 {
			scene.Proposal = nil
		}
	}
	scene.Reply = strings.TrimSpace(scene.Reply)
	scene.Actions = actions
	scene.Situation = strings.TrimSpace(scene.Situation)
	if utf8.RuneCountInString(scene.Situation) > 320 {
		scene.Situation = string([]rune(scene.Situation)[:320])
	}
	switch scene.Focus {
	case "ta", "window", "table", "screen", "ambient":
	default:
		scene.Focus = "ambient"
	}
	return scene, nil
}

// A stable brief keeps this paid experience from becoming an unrelated chat.
func momentExperienceBrief(location string) string {
	switch location {
	case "cafe":
		return "Minor situation: the drink you wanted is unavailable. Goal: discuss your different tastes, jointly choose an alternative drink and give this moment a name. Respect changing venue or another user-proposed solution."
	case "cinema":
		return "Minor situation: you prefer different kinds of films. Goal: discuss both preferences, jointly choose what kind of fictional movie night to have and a detail to remember. Do not invent having watched a film or its ending."
	case "restaurant":
		return "Minor situation: you want different dishes and must choose something to share. Goal: discuss both preferences, jointly agree on the imagined meal and a name for this evening. No real order or reservation is made."
	default:
		return "Goal: together decide how to commemorate the already delivered gift or media. Let the user and companion contribute a meaning and a name; preserve their differences. Never invent another purchase or media delivery."
	}
}

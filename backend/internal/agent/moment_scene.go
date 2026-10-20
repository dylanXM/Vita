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
	Affect    json.RawMessage           `json:"affect,omitempty"`
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
	case "ballroom":
		return "A warm romantic virtual ballroom date. Invite the user to choose a dance, slow the rhythm, or rest on the terrace. These are first-person scene actions without visible human bodies. React to their actual saved action, do not invent physical touch or a completed dance that did not occur. No mandatory challenge or task."
	case "cafe":
		return "A cozy romantic first-person cafe date. The user can select coffee or tea and raise a cup; those saved actions visibly change the table. React naturally to actual actions, remember their preferences, and invite relaxed conversation. Do not repeat a fixed sold-out-drink problem or force a task or naming exercise."
	case "cinema":
		return "A cozy virtual cinema date. The user can choose a romantic or mystery atmosphere, or pause to talk. The screen light changes, but this app does not stream a real film. React to their saved action and discuss preferences naturally. Never invent having watched a specific film, its scenes or its ending, and do not force a disagreement."
	case "restaurant":
		return "A romantic candlelit dinner. The user can share a meal, choose dessert or raise a glass. React naturally to the actual saved action and their preferences. Do not force a disagreement, naming task or real-world order."
	default:
		return "Goal: together decide how to commemorate the already delivered gift or media. Let the user and companion contribute a meaning and a name; preserve their differences. Never invent another purchase or media delivery."
	}
}

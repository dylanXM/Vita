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
func decodeMomentScene(raw string) (string, []momentSceneAction, error) {
	text := strings.TrimSpace(raw)
	if strings.HasPrefix(text, "```") {
		if newline := strings.IndexByte(text, '\n'); newline >= 0 {
			text = strings.TrimSpace(strings.TrimSuffix(text[newline+1:], "```"))
		}
	}
	if !strings.HasPrefix(text, "{") {
		return text, nil, nil
	}
	var scene struct {
		Reply   string              `json:"reply"`
		Actions []momentSceneAction `json:"actions"`
	}
	if err := json.Unmarshal([]byte(text), &scene); err != nil || strings.TrimSpace(scene.Reply) == "" {
		return "", nil, fmt.Errorf("shared scene returned an invalid reply")
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
	return strings.TrimSpace(scene.Reply), actions, nil
}

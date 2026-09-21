package agent

import (
	"context"
	"fmt"
)

type ModelTestAudio struct {
	Filename string
	MIMEType string
	Data     []byte
}

func TestModelScenario(ctx context.Context, client *Client, model Model, scenario string, audio *ModelTestAudio) error {
	switch scenario {
	case "text_chat":
		_, err := client.GenerateText(ctx, model, GenerateRequest{
			System:      "You are an AI companion in a private chat. Reply naturally and briefly.",
			Messages:    []ChatMessage{{Role: "user", Content: "Say hello in one short sentence."}},
			Temperature: 0.2, MaxTokens: 80,
		})
		return err
	case "text_character_profile":
		output, err := client.GenerateText(ctx, model, GenerateRequest{
			System:      "You create editable fictional AI character profiles. Output strict JSON only.",
			Messages:    []ChatMessage{{Role: "user", Content: `Return a JSON object for a fictional character named Mina with all fields: name, gender, persona, appearance, city, occupation, interests, personality_tags, speaking_style, likes, dislikes, life_habits, life_goal, backstory.`}},
			Temperature: 0.2, MaxTokens: 500,
		})
		if err != nil {
			return err
		}
		_, err = parseCharacterProfile(output)
		return err
	case "text_life_plan":
		output, err := client.GenerateText(ctx, model, GenerateRequest{
			System:      "You plan a believable daily timeline for a fictional AI companion. Output strict JSON only.",
			Messages:    []ChatMessage{{Role: "user", Content: `Return a JSON array containing one ordinary event. Include every field: type, title, description, location, start (HH:MM), end (HH:MM), emotion, importance (0-100), user_relevance (0-100), share (boolean), moment (boolean), moment_text, media_urls.`}},
			Temperature: 0.2, MaxTokens: 350,
		})
		if err != nil {
			return err
		}
		events, err := parseLifePlan(output)
		if err != nil {
			return err
		}
		if len(events) != 1 {
			return fmt.Errorf("provider returned an unexpected number of life plan events")
		}
		_, startOK := parseClockMinutes(events[0].Start)
		_, endOK := parseClockMinutes(events[0].End)
		if events[0].Title == "" || events[0].Description == "" || !startOK || !endOK {
			return fmt.Errorf("provider returned an incomplete life plan event")
		}
		return nil
	case "text_proactive":
		_, err := client.GenerateText(ctx, model, GenerateRequest{
			System:      "You write natural proactive messages from an AI companion.",
			Messages:    []ChatMessage{{Role: "user", Content: "Write one short, non-urgent check-in message."}},
			Temperature: 0.2, MaxTokens: 80,
		})
		return err
	case "image_life_photo":
		_, err := client.GenerateImage(ctx, model, GenerateImageRequest{Prompt: "A natural smartphone photo of a quiet afternoon coffee on a cafe table, no text", Size: "1024x1024"})
		return err
	case "image_requested_photo":
		_, err := client.GenerateImage(ctx, model, GenerateImageRequest{Prompt: "A natural smartphone photo of a city park in daylight, no text", Size: "1024x1024"})
		return err
	case "audio_speech":
		_, _, err := client.GenerateSpeech(ctx, model, "Hi, this is a voice reply test.", "alloy")
		return err
	case "audio_transcription":
		if audio == nil || len(audio.Data) == 0 {
			return fmt.Errorf("a test audio file is required")
		}
		_, err := client.TranscribeAudio(ctx, model, audio.Filename, audio.MIMEType, audio.Data)
		return err
	default:
		return fmt.Errorf("scenario %q has no runtime validation adapter", scenario)
	}
}

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

// ModelScenarioTest is the request/response transcript for one scenario test.
type ModelScenarioTest struct {
	Request  string
	Response string
}

// TestModelScenario runs one real scenario against the provider and records the
// request and response payloads so the admin console can inspect them.
func TestModelScenario(ctx context.Context, client *Client, model Model, scenario string, audio *ModelTestAudio) (ModelScenarioTest, error) {
	switch scenario {
	case "text_chat", "text_story_chapter", "text_storyboard":
		req := GenerateRequest{
			System:      "You are an AI companion in a private chat. Reply naturally and briefly.",
			Messages:    []ChatMessage{{Role: "user", Content: "Say hello in one short sentence."}},
			Temperature: 0.2, MaxTokens: 80,
		}
		out, err := client.GenerateText(ctx, model, req)
		return transcript(scenario, req, out), err
	case "text_character_profile":
		req := GenerateRequest{
			System:      "You create editable fictional AI character profiles. Output strict JSON only.",
			Messages:    []ChatMessage{{Role: "user", Content: `Return a JSON object for a fictional character named Mina with all fields: name, gender, persona, appearance, city, occupation, interests, personality_tags, speaking_style, likes, dislikes, life_habits, life_goal, backstory.`}},
			Temperature: 0.2, MaxTokens: 500,
		}
		out, err := client.GenerateText(ctx, model, req)
		if err != nil {
			return transcript(scenario, req, out), err
		}
		if _, err := parseCharacterProfile(out); err != nil {
			return transcript(scenario, req, out), err
		}
		return transcript(scenario, req, out), nil
	case "text_life_plan":
		req := GenerateRequest{
			System:      "You plan a believable daily timeline for a fictional AI companion. Output strict JSON only.",
			Messages:    []ChatMessage{{Role: "user", Content: `Return a JSON array containing one ordinary event. Include every field: type, title, description, location, start (HH:MM), end (HH:MM), emotion, importance (0-100), user_relevance (0-100), share (boolean), moment (boolean), moment_text, media_urls.`}},
			Temperature: 0.2, MaxTokens: 350,
		}
		out, err := client.GenerateText(ctx, model, req)
		if err != nil {
			return transcript(scenario, req, out), err
		}
		events, err := parseLifePlan(out)
		if err != nil {
			return transcript(scenario, req, out), err
		}
		if len(events) != 1 {
			return transcript(scenario, req, out), fmt.Errorf("provider returned an unexpected number of life plan events")
		}
		_, startOK := parseClockMinutes(events[0].Start)
		_, endOK := parseClockMinutes(events[0].End)
		if events[0].Title == "" || events[0].Description == "" || !startOK || !endOK {
			return transcript(scenario, req, out), fmt.Errorf("provider returned an incomplete life plan event")
		}
		return transcript(scenario, req, out), nil
	case "text_proactive":
		req := GenerateRequest{
			System:      "You write natural proactive messages from an AI companion.",
			Messages:    []ChatMessage{{Role: "user", Content: "Write one short, non-urgent check-in message."}},
			Temperature: 0.2, MaxTokens: 80,
		}
		out, err := client.GenerateText(ctx, model, req)
		return transcript(scenario, req, out), err
	case "image_life_photo":
		req := GenerateImageRequest{Prompt: "A natural smartphone photo of a quiet afternoon coffee on a cafe table, no text", Size: "1024x1024"}
		out, err := client.GenerateImage(ctx, model, req)
		return imageTranscript(scenario, req, out), err
	case "image_requested_photo", "image_storyboard_sheet":
		req := GenerateImageRequest{Prompt: "A natural smartphone photo of a city park in daylight, no text", Size: "1024x1024"}
		out, err := client.GenerateImage(ctx, model, req)
		return imageTranscript(scenario, req, out), err
	case "audio_speech":
		text, voice := "Hi, this is a voice reply test.", "alloy"
		audioOut, mimeType, err := client.GenerateSpeech(ctx, model, text, voice)
		request := fmt.Sprintf("text=%q voice=%q format=mp3", text, voice)
		response := fmt.Sprintf("mime=%s bytes=%d", mimeType, len(audioOut))
		return ModelScenarioTest{Request: request, Response: response}, err
	case "audio_transcription":
		if audio == nil || len(audio.Data) == 0 {
			return ModelScenarioTest{}, fmt.Errorf("a test audio file is required")
		}
		out, err := client.TranscribeAudio(ctx, model, audio.Filename, audio.MIMEType, audio.Data)
		request := fmt.Sprintf("file=%q mime=%s bytes=%d", audio.Filename, audio.MIMEType, len(audio.Data))
		return ModelScenarioTest{Request: request, Response: out}, err
	default:
		return ModelScenarioTest{}, fmt.Errorf("scenario %q has no runtime validation adapter", scenario)
	}
}

func transcript(scenario string, req GenerateRequest, response string) ModelScenarioTest {
	return ModelScenarioTest{
		Request:  fmt.Sprintf("system=%q user=%q temperature=%.2f max_tokens=%d", req.System, req.Messages[0].Content, req.Temperature, req.MaxTokens),
		Response: response,
	}
}

func imageTranscript(scenario string, req GenerateImageRequest, response string) ModelScenarioTest {
	return ModelScenarioTest{
		Request:  fmt.Sprintf("prompt=%q size=%s n=1", req.Prompt, req.Size),
		Response: response,
	}
}

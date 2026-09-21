package handler

import (
	"errors"
	"strings"
	"testing"
)

func mediaRouteFixture() []mediaModelRoute {
	return []mediaModelRoute{
		{RouteKey: "text_chat", MediaType: "text"},
		{RouteKey: "text_life_plan", MediaType: "text"},
		{RouteKey: "text_proactive", MediaType: "text"},
		{RouteKey: "text_character_profile", MediaType: "text"},
		{RouteKey: "text_story_chapter", MediaType: "text"},
		{RouteKey: "text_storyboard", MediaType: "text"},
		{RouteKey: "image_life_photo", MediaType: "image"},
		{RouteKey: "image_requested_photo", MediaType: "image"},
		{RouteKey: "image_storyboard_sheet", MediaType: "image"},
		{RouteKey: "audio_transcription", MediaType: "audio"},
		{RouteKey: "audio_speech", MediaType: "audio"},
		{RouteKey: "video_life_clip", MediaType: "video"},
		{RouteKey: "video_realtime_avatar", MediaType: "video"},
	}
}

func TestCollectModelTestResultsKeepsFailuresInformational(t *testing.T) {
	results := collectModelTestResults([]string{"text_chat", "video_life_clip"}, func(scenario string) error {
		if scenario == "video_life_clip" {
			return errors.New("adapter unavailable")
		}
		return nil
	})
	if len(results) != 2 || !results[0].Success || results[1].Success || results[1].Error != "adapter unavailable" {
		t.Fatalf("results = %#v", results)
	}
}

func stringPointer(value string) *string { return &value }

func TestNormalizeMediaModelRoutesCleansOptionalValues(t *testing.T) {
	routes := mediaRouteFixture()
	routes[0].Enabled = true
	routes[0].PrimaryModelID = stringPointer(" image-primary ")
	routes[0].FallbackModelIDs = []string{" image-backup-1 ", "", " image-backup-2 ", "   "}
	routes[1].PrimaryModelID = stringPointer("  ")

	normalized, err := normalizeMediaModelRoutes(routes)
	if err != nil {
		t.Fatal(err)
	}
	if normalized[0].PrimaryModelID == nil || *normalized[0].PrimaryModelID != "image-primary" {
		t.Fatalf("primary model = %#v", normalized[0].PrimaryModelID)
	}
	if len(normalized[0].FallbackModelIDs) != 2 || normalized[0].FallbackModelIDs[0] != "image-backup-1" || normalized[0].FallbackModelIDs[1] != "image-backup-2" {
		t.Fatalf("fallback models = %#v", normalized[0].FallbackModelIDs)
	}
	if normalized[1].PrimaryModelID != nil {
		t.Fatalf("blank optional primary model was not removed: %#v", normalized[1].PrimaryModelID)
	}
}

func TestNormalizeMediaModelRoutesRejectsInvalidConfiguration(t *testing.T) {
	tests := map[string]func([]mediaModelRoute) []mediaModelRoute{
		"missing route": func(routes []mediaModelRoute) []mediaModelRoute { return routes[:len(routes)-1] },
		"wrong media type": func(routes []mediaModelRoute) []mediaModelRoute {
			routes[0].MediaType = "audio"
			return routes
		},
		"duplicate route": func(routes []mediaModelRoute) []mediaModelRoute {
			routes[1] = routes[0]
			return routes
		},
		"enabled without primary": func(routes []mediaModelRoute) []mediaModelRoute {
			routes[0].Enabled = true
			return routes
		},
		"duplicate models": func(routes []mediaModelRoute) []mediaModelRoute {
			routes[0].PrimaryModelID = stringPointer("same")
			routes[0].FallbackModelIDs = []string{"same"}
			return routes
		},
		"too many fallbacks": func(routes []mediaModelRoute) []mediaModelRoute {
			routes[0].FallbackModelIDs = []string{"1", "2", "3", "4", "5", "6"}
			return routes
		},
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := normalizeMediaModelRoutes(mutate(mediaRouteFixture()))
			if err == nil || strings.TrimSpace(err.Error()) == "" {
				t.Fatal("expected a descriptive validation error")
			}
		})
	}
}

func TestNormalizeModelScenariosDerivesCapabilities(t *testing.T) {
	scenarios, capabilities, err := normalizeModelScenarios([]string{"text_chat", "image_life_photo", "audio_speech"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(scenarios, ",") != "text_chat,image_life_photo,audio_speech" {
		t.Fatalf("scenarios = %#v", scenarios)
	}
	if strings.Join(capabilities, ",") != "text,image,audio" {
		t.Fatalf("capabilities = %#v", capabilities)
	}
}

func TestNormalizeModelScenariosRejectsUntestableAndDuplicateScenarios(t *testing.T) {
	for _, scenarios := range [][]string{{}, {"unknown_scene"}, {"text_chat", "text_chat"}} {
		if _, _, err := normalizeModelScenarios(scenarios); err == nil {
			t.Fatalf("expected validation error for %#v", scenarios)
		}
	}
}

func TestNormalizeSubscriptionPlanIDs(t *testing.T) {
	got, err := normalizeSubscriptionPlanIDs([]string{" plan-a ", "", "plan-b"})
	if err != nil {
		t.Fatalf("normalize subscription plans: %v", err)
	}
	if strings.Join(got, ",") != "plan-a,plan-b" {
		t.Fatalf("subscription plans = %v", got)
	}
	if _, err := normalizeSubscriptionPlanIDs([]string{"plan-a", " plan-a "}); err == nil {
		t.Fatal("expected duplicate subscription plan to be rejected")
	}
}

func TestNormalizeModelScenariosAllowsVideoWithoutRequiringATestAdapter(t *testing.T) {
	_, capabilities, err := normalizeModelScenarios([]string{"video_life_clip"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(capabilities, ",") != "video" {
		t.Fatalf("capabilities = %#v", capabilities)
	}
}

func TestScenariosForCapabilitiesKeepsLegacyCreateRequestsCompatible(t *testing.T) {
	scenarios, err := scenariosForCapabilities([]string{"text", "audio"})
	if err != nil {
		t.Fatal(err)
	}
	want := "text_chat,text_life_plan,text_proactive,text_character_profile,text_story_chapter,text_storyboard,audio_transcription,audio_speech"
	if strings.Join(scenarios, ",") != want {
		t.Fatalf("scenarios = %#v", scenarios)
	}
}

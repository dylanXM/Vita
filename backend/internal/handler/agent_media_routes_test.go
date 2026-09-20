package handler

import (
	"strings"
	"testing"
)

func mediaRouteFixture() []mediaModelRoute {
	return []mediaModelRoute{
		{RouteKey: "text_chat", MediaType: "text"},
		{RouteKey: "text_life_plan", MediaType: "text"},
		{RouteKey: "text_proactive", MediaType: "text"},
		{RouteKey: "image_life_photo", MediaType: "image"},
		{RouteKey: "image_requested_photo", MediaType: "image"},
		{RouteKey: "audio_transcription", MediaType: "audio"},
		{RouteKey: "audio_speech", MediaType: "audio"},
		{RouteKey: "video_life_clip", MediaType: "video"},
		{RouteKey: "video_realtime_avatar", MediaType: "video"},
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

package handler

import "testing"

func TestValidStoryboardPanelCount(t *testing.T) {
	for _, value := range []int{4, 6, 8, 9} {
		if !validStoryboardPanelCount(value) {
			t.Fatalf("expected %d panels to be allowed", value)
		}
	}
	for _, value := range []int{0, 1, 5, 7, 10, 12} {
		if validStoryboardPanelCount(value) {
			t.Fatalf("expected %d panels to be rejected", value)
		}
	}
}

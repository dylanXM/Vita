package handler

import "testing"

func TestDateSceneActionRejectsCrossSceneAndUnknownActions(t *testing.T) {
	for _, tc := range []struct {
		location, action string
		allowed          bool
	}{
		{"cinema", "romance", true}, {"cinema", "pause", true}, {"cinema", "coffee", false},
		{"cafe", "tea", true}, {"restaurant", "dessert", true}, {"ballroom", "slow_dance", true},
		{"cafe", "dance", false}, {"restaurant", "coffee", false}, {"ballroom", "toast", false},
		{"cinema", "dance", false}, {"cafe", "", false}, {"cafe", "purchase", false},
	} {
		if got := validDateSceneAction(tc.location, tc.action); got != tc.allowed {
			t.Errorf("%s/%s: got %v", tc.location, tc.action, got)
		}
	}
}

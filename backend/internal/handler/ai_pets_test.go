package handler

import (
	"testing"
	"time"
)

func TestDecayPetState(t *testing.T) {
	start := time.Date(2026, 9, 21, 10, 0, 0, 0, time.UTC)
	state, hours := decayPetState(petStateResponse{Hunger: 80, Happiness: 70, Energy: 80, Health: 100}, start, start.Add(10*time.Hour))
	if hours != 10 || state.Hunger != 60 || state.Happiness != 60 || state.Energy != 75 || state.Health != 100 {
		t.Fatalf("unexpected decayed state: hours=%d state=%+v", hours, state)
	}
}

func TestDecayPetStateCapsAndAffectsHealth(t *testing.T) {
	start := time.Date(2026, 9, 21, 10, 0, 0, 0, time.UTC)
	state, hours := decayPetState(petStateResponse{Hunger: 10, Happiness: 20, Energy: 20, Health: 90}, start, start.Add(100*time.Hour))
	if hours != 72 || state.Hunger != 0 || state.Happiness != 0 || state.Energy != 0 || state.Health != 66 {
		t.Fatalf("unexpected capped state: hours=%d state=%+v", hours, state)
	}
}

func TestUniqueStrings(t *testing.T) {
	got := uniqueStrings([]string{" plan-a ", "plan-a", "", "plan-b"})
	if len(got) != 2 || got[0] != "plan-a" || got[1] != "plan-b" {
		t.Fatalf("unexpected values: %#v", got)
	}
}

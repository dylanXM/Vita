package handler

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestDecayPetState(t *testing.T) {
	start := time.Date(2026, 9, 21, 10, 0, 0, 0, time.UTC)
	state, hours := decayPetState(petStateResponse{Hunger: 80, Hydration: 80, Happiness: 70, Energy: 80, Health: 100}, start, start.Add(10*time.Hour))
	if hours != 10 || state.Hunger != 60 || state.Hydration != 60 || state.Happiness != 60 || state.Energy != 75 || state.Health != 100 {
		t.Fatalf("unexpected decayed state: hours=%d state=%+v", hours, state)
	}
}

func TestDecayPetStateCapsAndAffectsHealth(t *testing.T) {
	start := time.Date(2026, 9, 21, 10, 0, 0, 0, time.UTC)
	state, hours := decayPetState(petStateResponse{Hunger: 10, Hydration: 10, Happiness: 20, Energy: 20, Health: 90}, start, start.Add(100*time.Hour))
	if hours != 72 || state.Hunger != 0 || state.Hydration != 0 || state.Happiness != 0 || state.Energy != 0 || state.Health != 66 {
		t.Fatalf("unexpected capped state: hours=%d state=%+v", hours, state)
	}
}

func TestPetCareUpdatesPersistentVitals(t *testing.T) {
	state := petStateResponse{Hunger: 50, Hydration: 40, Happiness: 50, Energy: 60, Health: 90, Experience: 95, Level: 1}
	if !applyPetCare(&state, "walk") {
		t.Fatal("walk should be allowed")
	}
	if state.Hunger != 45 || state.Hydration != 34 || state.Happiness != 62 || state.Energy != 48 || state.Experience != 105 || state.Level != 2 {
		t.Fatalf("unexpected care result: %+v", state)
	}
	if !applyPetCare(&state, "drink") || state.Hydration != 64 {
		t.Fatalf("drink did not replenish hydration: %+v", state)
	}
	if !applyPetCare(&state, "rest") || state.Energy != 68 {
		t.Fatalf("rest did not restore energy: %+v", state)
	}
}

func TestPetCareRejectsUnsafeWalkWithoutMutation(t *testing.T) {
	state := petStateResponse{Hunger: 50, Hydration: 9, Happiness: 50, Energy: 60, Health: 90, Experience: 10, Level: 1}
	if applyPetCare(&state, "walk") {
		t.Fatal("walk should require water")
	}
	if state.Hunger != 50 || state.Hydration != 9 || state.Energy != 60 || state.Experience != 10 {
		t.Fatalf("rejected walk mutated state: %+v", state)
	}
}

func TestUniqueStrings(t *testing.T) {
	got := uniqueStrings([]string{" plan-a ", "plan-a", "", "plan-b"})
	if len(got) != 2 || got[0] != "plan-a" || got[1] != "plan-b" {
		t.Fatalf("unexpected values: %#v", got)
	}
}

func TestWriteAIPetBreedDeleteResult(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, test := range []struct {
		err          error
		rowsAffected int64
		status       int
		bodyContains string
	}{
		{nil, 1, http.StatusOK, "AI pet breed deleted"},
		{nil, 0, http.StatusNotFound, "AI pet breed not found"},
		{errors.New("database unavailable"), 0, http.StatusInternalServerError, "failed to delete AI pet breed"},
	} {
		recorder := httptest.NewRecorder()
		context, _ := gin.CreateTestContext(recorder)
		writeAIPetBreedDeleteResult(context, test.err, test.rowsAffected)
		if recorder.Code != test.status || !strings.Contains(recorder.Body.String(), test.bodyContains) {
			t.Fatalf("delete result (err=%v, rows=%d) produced %d %s; want %d containing %q", test.err, test.rowsAffected, recorder.Code, recorder.Body.String(), test.status, test.bodyContains)
		}
	}
}

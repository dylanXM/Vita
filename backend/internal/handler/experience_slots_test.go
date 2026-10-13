package handler

import (
	"testing"
	"time"
)

func TestAvailableExperienceSlots(t *testing.T) {
	now := time.Date(2026, 10, 13, 7, 3, 0, 0, time.UTC)
	blocks := []experienceBlock{{Start: now.Add(30 * time.Minute), End: now.Add(2 * time.Hour)}}
	slots := availableExperienceSlots(now, time.Hour, blocks)
	if len(slots) != 12 {
		t.Fatalf("want 12 slots, got %d", len(slots))
	}
	for _, slot := range slots {
		if slot.StartsAt.Before(now.Add(10 * time.Minute)) {
			t.Fatal("offered an expiring slot")
		}
		if !fitsExperienceSlot(slot.StartsAt, time.Hour, blocks) {
			t.Fatalf("offered overlapping slot: %v", slot)
		}
		if slot.EndsAt.Sub(slot.StartsAt) != time.Hour {
			t.Fatal("wrong duration")
		}
	}
}

func TestSlotBoundaryAndEmptySchedule(t *testing.T) {
	now := time.Date(2026, 10, 13, 7, 0, 0, 0, time.UTC)
	block := experienceBlock{now, now.Add(time.Hour)}
	if !fitsExperienceSlot(block.End, time.Hour, []experienceBlock{block}) {
		t.Fatal("adjacent times must not overlap")
	}
	if fitsExperienceSlot(now.Add(30*time.Minute), time.Hour, []experienceBlock{block}) {
		t.Fatal("overlap accepted")
	}
	if len(availableExperienceSlots(now, time.Hour, []experienceBlock{{now, now.Add(8 * 24 * time.Hour)}})) != 0 {
		t.Fatal("fully blocked schedule offered a slot")
	}
	if len(availableExperienceSlots(now, 0, nil)) != 0 {
		t.Fatal("invalid duration offered slots")
	}
}

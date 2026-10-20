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

func TestDateBookingStartHours(t *testing.T) {
	location, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"date_coffee", "date_dinner", "date_movie"} {
		for _, clock := range []struct{ hour, minute int }{{5, 59}, {6, 0}, {17, 59}, {18, 0}, {21, 59}, {22, 0}, {23, 0}, {0, 0}} {
			start := time.Date(2026, 10, 13, clock.hour, clock.minute, 0, 0, location)
			want := clock.hour >= 6 && clock.hour < 22
			if key == "date_dinner" || key == "date_movie" {
				want = clock.hour >= 18 && clock.hour < 22
			}
			if got := dateBookingWindow(key, location).allows(start.UTC()); got != want {
				t.Fatalf("%s %s got=%v want=%v", key, start, got, want)
			}
		}
	}
	now := time.Date(2026, 10, 13, 21, 0, 0, 0, location)
	slots := availableExperienceSlots(now, 150*time.Minute, nil, dateBookingWindow("date_movie", location))
	if len(slots) == 0 || slots[0].StartsAt.In(location).Hour() != 21 || slots[0].EndsAt.In(location).Hour() < 23 {
		t.Fatal("movie end time was incorrectly limited")
	}
	for _, slot := range slots {
		if !dateBookingWindow("date_movie", location).allows(slot.StartsAt) {
			t.Fatal("invalid movie slot offered")
		}
	}
}

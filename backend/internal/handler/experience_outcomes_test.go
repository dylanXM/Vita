package handler

import "testing"

func TestOutcomeIdentity(t *testing.T) {
	for _, pair := range [][2]string{{"", ""}, {"event", "spend"}} {
		if _, err := outcomeIdentity(pair[0], pair[1]); err == nil {
			t.Fatalf("accepted ambiguous reference: %v", pair)
		}
	}
	event, err := outcomeIdentity("same", "")
	if err != nil {
		t.Fatal(err)
	}
	repeated, _ := outcomeIdentity("same", "")
	spend, _ := outcomeIdentity("", "same")
	if event != repeated || event == spend {
		t.Fatalf("unstable or colliding keys: %q %q %q", event, repeated, spend)
	}
}

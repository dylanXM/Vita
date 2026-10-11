package credits

import (
	"errors"
	"testing"
)

func TestCheckAvailability(t *testing.T) {
	for _, test := range []struct {
		name                            string
		launched, exclusive, subscribed bool
		want                            error
	}{
		{"upcoming public", false, false, false, ErrNotLaunched},
		{"upcoming exclusive subscriber", false, true, true, ErrNotLaunched},
		{"exclusive guest", true, true, false, ErrSubscriptionRequired},
		{"exclusive subscriber", true, true, true, nil},
		{"public guest", true, false, false, nil},
		{"public subscriber", true, false, true, nil},
	} {
		t.Run(test.name, func(t *testing.T) {
			err := CheckAvailability(Product{IsLaunched: test.launched, SubscriptionOnly: test.exclusive}, test.subscribed)
			if !errors.Is(err, test.want) {
				t.Fatalf("got %v, want %v", err, test.want)
			}
		})
	}
}

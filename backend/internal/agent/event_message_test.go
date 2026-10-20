package agent

import "testing"

func TestCompleteEventMessage(t *testing.T) {
	for _, item := range []struct {
		text  string
		valid bool
	}{
		{"小组作业的初", false},
		{"把小组作业的初稿整理完了。", true},
		{"The draft is ready.", true},
		{"你觉得呢？", true},
		{"今天挺开心😊", true},
		{"我很喜欢❤️", true},
		{"", false},
	} {
		if got := completeEventMessage(item.text); got != item.valid {
			t.Errorf("%q: got %v want %v", item.text, got, item.valid)
		}
	}
}

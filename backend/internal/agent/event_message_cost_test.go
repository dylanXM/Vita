package agent

import "testing"

func TestEventTextAlreadyLocalized(t *testing.T) {
	good := eventMessageText{Content: "今天把稿子写完了。", Title: "完成稿件", Description: "在宿舍整理稿件", Location: "宿舍"}
	for _, tc := range []struct {
		name, locale string
		input        eventMessageText
		want         bool
	}{
		{"complete Chinese", "zh-CN", good, true},
		{"Latin language needs validation", "en", eventMessageText{Content: "Finished today.", Title: "Finished"}, false},
		{"unfinished content", "zh-Hans", eventMessageText{Content: "今天把稿子", Title: "完成稿件"}, false},
		{"English event", "zh-Hans", eventMessageText{Content: "写完了。", Title: "Long walk"}, false},
		{"English location", "zh-Hans", eventMessageText{Content: "写完了。", Title: "完成稿件", Location: "Dormitory"}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := eventTextAlreadyLocalized(tc.locale, tc.input); got != tc.want {
				t.Fatalf("got %v want %v", got, tc.want)
			}
		})
	}
}

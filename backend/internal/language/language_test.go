package language

import "testing"

func TestNormalize(t *testing.T) {
	tests := map[string]string{
		"ar-SA": "ar", "en-US": "en", "es-MX": "es", "ja-JP": "ja",
		"ko-KR": "ko", "pt-BR": "pt", "zh-CN": "zh-Hans", "zh-Hant": "zh-Hant",
		"ru-RU": "en", "": "en",
	}
	for input, want := range tests {
		if got := Normalize(input); got != want {
			t.Fatalf("Normalize(%q) = %q, want %q", input, got, want)
		}
	}
}

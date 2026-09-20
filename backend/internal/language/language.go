package language

import "strings"

const English = "en"

// Normalize returns one of the eight App locale tags. Unsupported or malformed
// values deliberately fall back to English.
func Normalize(raw string) string {
	value := strings.ToLower(strings.TrimSpace(strings.Split(raw, ",")[0]))
	value = strings.TrimSpace(strings.Split(value, ";")[0])
	value = strings.ReplaceAll(value, "_", "-")
	switch {
	case value == "ar" || strings.HasPrefix(value, "ar-"):
		return "ar"
	case value == "es" || strings.HasPrefix(value, "es-"):
		return "es"
	case value == "ja" || strings.HasPrefix(value, "ja-"):
		return "ja"
	case value == "ko" || strings.HasPrefix(value, "ko-"):
		return "ko"
	case value == "pt" || strings.HasPrefix(value, "pt-"):
		return "pt"
	case value == "zh-hant" || strings.HasPrefix(value, "zh-hant-") || value == "zh-tw" || value == "zh-hk" || value == "zh-mo":
		return "zh-Hant"
	case value == "zh" || value == "zh-hans" || strings.HasPrefix(value, "zh-hans-") || value == "zh-cn" || value == "zh-sg":
		return "zh-Hans"
	case value == "en" || strings.HasPrefix(value, "en-"):
		return English
	default:
		return English
	}
}

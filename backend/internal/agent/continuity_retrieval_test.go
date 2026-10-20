package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestMemorySearchSupportsChineseAndLiteralLatinTerms(t *testing.T) {
	terms := memorySearchTerms("你还记得我的面试吗？ INTERVIEW interview 100% _")
	seen := map[string]bool{}
	for _, term := range terms {
		if seen[term] {
			t.Fatal("duplicate term")
		}
		seen[term] = true
	}
	if !seen["面试"] || !seen["interview"] || seen["%"] || seen["_"] {
		t.Fatalf("terms=%v", terms)
	}
	if len(memorySearchTerms(strings.Repeat("不同问题english ", 100))) > 32 {
		t.Fatal("unbounded search")
	}
	if memorySearchJSON("") != "[]" {
		t.Fatal("empty query is not JSON array")
	}
}

func TestLanguageRepairPreservesSourceAndRejectsWrongScript(t *testing.T) {
	source := "I remember your interview, but do not know its outcome."
	output := "我记得你的面试，但还不知道结果。"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Messages []ChatMessage `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Error(err)
		}
		found := false
		for _, message := range req.Messages {
			if strings.Contains(message.Content, source) {
				found = true
			}
		}
		if !found {
			t.Error("translation lost actual source")
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": output}}}})
	}))
	defer server.Close()
	service := &Service{client: NewClient()}
	models := []Model{{ID: "translate", Kind: "openai", BaseURL: server.URL, ModelName: "translate"}}
	got, err := service.repairMessageLanguage(context.Background(), "", "reply_language", models, source, "zh-Hans")
	if err != nil || got != output {
		t.Fatalf("got=%q err=%v", got, err)
	}
	output = "Still English."
	if _, err = service.repairMessageLanguage(context.Background(), "", "reply_language", models, source, "zh-Hans"); err == nil {
		t.Fatal("accepted wrong script")
	}
}

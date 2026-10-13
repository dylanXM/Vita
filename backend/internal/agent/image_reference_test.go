package agent

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestBuiltInPortraitReferences(t *testing.T) {
	s := &Service{client: NewClient()}
	for _, name := range []string{"mia", "nora", "leo", "kai"} {
		ref, err := s.loadPortraitReference(context.Background(), "user", "asset://assets/companions/"+name+".png")
		if err != nil || len(ref.Data) == 0 || ref.MIME != "image/png" {
			t.Fatalf("%s: %v", name, err)
		}
		raw, _ := json.Marshal(ref)
		if bytes.Contains(raw, []byte(base64.StdEncoding.EncodeToString(ref.Data))) {
			t.Fatal("raw portrait leaked into request history")
		}
	}
	if _, err := s.loadPortraitReference(context.Background(), "user", ""); err == nil {
		t.Fatal("missing portrait accepted")
	}
}

func TestPortraitReferenceUsesOpenAIEdit(t *testing.T) {
	ref, _ := (&Service{client: NewClient()}).loadPortraitReference(context.Background(), "user", "asset://assets/companions/mia.png")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/images/edits" {
			t.Errorf("path=%s", r.URL.Path)
		}
		if err := r.ParseMultipartForm(20 << 20); err != nil {
			t.Fatal(err)
		}
		defer r.MultipartForm.RemoveAll()
		f, _, err := r.FormFile("image")
		if err != nil {
			t.Fatal(err)
		}
		defer f.Close()
		data, _ := io.ReadAll(f)
		if !bytes.Equal(data, ref.Data) {
			t.Fatal("wrong portrait sent")
		}
		if r.FormValue("prompt") != "same person" || r.FormValue("input_fidelity") != "high" {
			t.Fatal("edit parameters missing")
		}
		_, _ = w.Write([]byte(`{"data":[{"url":"https://example.test/result.png"}]}`))
	}))
	defer server.Close()
	result, err := NewClient().GenerateImage(context.Background(), Model{Kind: "openai", ModelName: "gpt-image-1.5", BaseURL: server.URL}, GenerateImageRequest{Prompt: "same person", Size: "1024x1024", Reference: ref})
	if err != nil || result != "https://example.test/result.png" {
		t.Fatalf("result=%s err=%v", result, err)
	}
}

func TestKiePortraitReferenceUploadAndEdit(t *testing.T) {
	ref, _ := (&Service{client: NewClient()}).loadPortraitReference(context.Background(), "user", "asset://assets/companions/mia.png")
	for _, modelName := range []string{"gpt-image-2-5-sunburst-text-to-image", "google/nano-banana-edit"} {
		t.Run(modelName, func(t *testing.T) {
			uploaded := false
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") != "Bearer test-key" {
					t.Fatal("missing provider authorization")
				}
				switch r.URL.Path {
				case "/upload":
					var body map[string]string
					_ = json.NewDecoder(r.Body).Decode(&body)
					if body["base64Data"] != "data:image/png;base64,"+base64.StdEncoding.EncodeToString(ref.Data) {
						t.Fatal("wrong portrait uploaded")
					}
					uploaded = true
					_, _ = w.Write([]byte(`{"code":200,"success":true,"data":{"downloadUrl":"https://example.test/reference.png"}}`))
				case "/api/v1/jobs/createTask":
					if !uploaded {
						t.Fatal("generation preceded reference upload")
					}
					var body struct {
						Model string         `json:"model"`
						Input map[string]any `json:"input"`
					}
					_ = json.NewDecoder(r.Body).Decode(&body)
					field := "input_urls"
					if modelName == "google/nano-banana-edit" {
						field = "image_urls"
					} else if body.Model != "gpt-image-2-5-sunburst-image-to-image" {
						t.Fatal("text-to-image used without identity")
					}
					urls, ok := body.Input[field].([]any)
					if !ok || len(urls) != 1 || urls[0] != "https://example.test/reference.png" {
						t.Fatalf("missing reference: %v", body.Input)
					}
					_, _ = w.Write([]byte(`{"code":200,"data":{"taskId":"reference-task"}}`))
				case "/api/v1/jobs/recordInfo":
					_ = json.NewEncoder(w).Encode(map[string]any{"code": 200, "data": map[string]any{"state": "success", "resultJson": `{"resultUrls":["https://example.test/result.png"]}`}})
				default:
					t.Fatalf("unexpected %s", r.URL.Path)
				}
			}))
			defer server.Close()
			c := NewClient()
			c.kieUploadURL = server.URL + "/upload"
			result, err := c.GenerateImage(context.Background(), Model{Kind: "kie", ModelName: modelName, BaseURL: server.URL, APIKey: "test-key"}, GenerateImageRequest{Prompt: "same person", Size: "1024x1024", Reference: ref})
			if err != nil || result != "https://example.test/result.png" {
				t.Fatalf("result=%s err=%v", result, err)
			}
		})
	}
}

func TestUnsupportedKieReferenceNeverFallsBackToTextOnly(t *testing.T) {
	ref := &ImageReference{Data: []byte("portrait"), MIME: "image/png"}
	_, err := NewClient().GenerateImage(context.Background(), Model{Kind: "kie", ModelName: "imagen4"}, GenerateImageRequest{Reference: ref})
	if err == nil || !strings.Contains(err.Error(), "portrait-reference adapter") {
		t.Fatalf("err=%v", err)
	}
}

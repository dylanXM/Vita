package agent

import (
	"bytes"
	"context"
	"embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"strings"

	"github.com/google/uuid"
)

//go:embed portraits/*.png
var builtInPortraits embed.FS

const portraitIdentityPrompt = " Use the supplied portrait as the identity reference. Depict exactly that same person: preserve facial structure, age, skin tone, eye shape and hair identity. Change only the requested clothing, pose and scene. Do not substitute a different model or person."

func (s *Service) companionImageReference(ctx context.Context, userID, companionID string) (*ImageReference, error) {
	var source string
	err := s.db.QueryRowContext(ctx, `SELECT COALESCE(NULLIF(c.avatar_url,''),p.image_url,'') FROM companions c LEFT JOIN companion_portraits p ON p.id=c.portrait_id WHERE c.id=$1 AND c.user_id=$2`, companionID, userID).Scan(&source)
	if err != nil {
		return nil, err
	}
	return s.loadPortraitReference(ctx, userID, source)
}

func (s *Service) loadPortraitReference(ctx context.Context, userID, source string) (*ImageReference, error) {
	ref := &ImageReference{Source: source}
	var err error
	switch {
	case strings.HasPrefix(source, "asset://assets/companions/"):
		name := strings.TrimPrefix(source, "asset://assets/companions/")
		switch name {
		case "mia.png", "nora.png", "leo.png", "kai.png":
		default:
			return nil, fmt.Errorf("unknown built-in portrait")
		}
		ref.Data, err = builtInPortraits.ReadFile("portraits/" + name)
		ref.MIME = "image/png"
	case strings.HasPrefix(source, "/v1/media/"):
		if s.media == nil {
			return nil, fmt.Errorf("portrait media storage is unavailable")
		}
		ref.MIME, ref.Data, err = s.media.LoadBytes(ctx, strings.TrimPrefix(source, "/v1/media/"), userID)
	case strings.HasPrefix(source, "/v1/admin-images/"):
		if s.media == nil {
			return nil, fmt.Errorf("portrait media storage is unavailable")
		}
		asset, e := s.media.OpenAdminImage(ctx, strings.TrimPrefix(source, "/v1/admin-images/"))
		if e != nil {
			return nil, e
		}
		defer asset.Body.Close()
		ref.Data, err = io.ReadAll(io.LimitReader(asset.Body, (16<<20)+1))
		ref.MIME = asset.MimeType
	case strings.HasPrefix(source, "https://"), strings.HasPrefix(source, "http://"), strings.HasPrefix(source, "data:image/"):
		ref.Data, ref.MIME, err = s.client.downloadPaidImage(ctx, source)
	default:
		return nil, fmt.Errorf("companion portrait is missing or unsupported")
	}
	if err != nil {
		return nil, err
	}
	if len(ref.Data) == 0 || len(ref.Data) > 16<<20 || !strings.HasPrefix(http.DetectContentType(ref.Data), "image/") {
		return nil, fmt.Errorf("portrait reference is not a valid image")
	}
	ref.MIME = http.DetectContentType(ref.Data)
	return ref, nil
}

func (c *Client) uploadKieReference(ctx context.Context, model Model, ref *ImageReference) (string, error) {
	endpoint := c.kieUploadURL
	if endpoint == "" {
		endpoint = "https://kieai.redpandaai.co/api/file-base64-upload"
	}
	extension := ".png"
	if ref.MIME == "image/jpeg" {
		extension = ".jpg"
	} else if ref.MIME == "image/webp" {
		extension = ".webp"
	}
	body := map[string]any{"base64Data": "data:" + ref.MIME + ";base64," + base64.StdEncoding.EncodeToString(ref.Data), "uploadPath": "vita/portrait-references", "fileName": uuid.New().String() + extension}
	var response struct {
		Code    int  `json:"code"`
		Success bool `json:"success"`
		Data    struct {
			URL string `json:"downloadUrl"`
		} `json:"data"`
	}
	if err := c.doJSON(ctx, endpoint, model.APIKey, "", body, &response); err != nil {
		return "", err
	}
	if response.Code != 200 || !response.Success || !strings.HasPrefix(response.Data.URL, "https://") {
		return "", fmt.Errorf("KIE portrait upload failed")
	}
	return response.Data.URL, nil
}

func (c *Client) editImage(ctx context.Context, model Model, input GenerateImageRequest) (string, error) {
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	for key, value := range map[string]string{"model": model.ModelName, "prompt": input.Prompt, "size": input.Size, "n": "1"} {
		if value != "" {
			if err := writer.WriteField(key, value); err != nil {
				return "", err
			}
		}
	}
	if model.ModelName == "gpt-image-1" || model.ModelName == "gpt-image-1.5" {
		_ = writer.WriteField("input_fidelity", "high")
	}
	header := textproto.MIMEHeader{}
	header.Set("Content-Disposition", `form-data; name="image"; filename="portrait.png"`)
	header.Set("Content-Type", input.Reference.MIME)
	part, err := writer.CreatePart(header)
	if err != nil {
		return "", err
	}
	if _, err = part.Write(input.Reference.Data); err != nil {
		return "", err
	}
	if err = writer.Close(); err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, providerEndpoint(defaultBaseURL(model.Kind, model.BaseURL), "/images/edits"), &body)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+model.APIKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxImageProviderResponseBytes+1))
	if err != nil {
		return "", err
	}
	if len(raw) > maxImageProviderResponseBytes {
		return "", fmt.Errorf("image edit response too large")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("image edit returned %s: %s", resp.Status, truncate(string(raw), 500))
	}
	if trace, ok := ctx.Value(callTraceKey{}).(*callTrace); ok {
		trace.readUsage(raw)
	}
	var output struct {
		Data []struct {
			URL    string `json:"url"`
			Base64 string `json:"b64_json"`
		} `json:"data"`
	}
	if err = json.Unmarshal(raw, &output); err != nil {
		return "", err
	}
	if len(output.Data) == 0 {
		return "", fmt.Errorf("image edit returned no image")
	}
	if output.Data[0].URL != "" {
		return output.Data[0].URL, nil
	}
	if output.Data[0].Base64 != "" {
		return "data:image/png;base64," + output.Data[0].Base64, nil
	}
	return "", fmt.Errorf("image edit returned empty media")
}

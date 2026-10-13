package agent

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

// GenerateOutfitPhoto prepares media without granting ownership or charging.
func (s *Service) GenerateOutfitPhoto(ctx context.Context, userID, companionID, productKey, style string, preferences ...string) (*SavedMessage, error) {
	var name, appearance string
	if err := s.db.QueryRowContext(ctx, `SELECT name,COALESCE(appearance,'') FROM companions WHERE id=$1 AND user_id=$2 AND active=true AND deleted_at IS NULL`, companionID, userID).Scan(&name, &appearance); err != nil {
		return nil, err
	}
	models, err := s.loadModelRouteModels(ctx, "image_requested_photo", userID)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(style) == "" {
		return nil, fmt.Errorf("outfit style is not configured")
	}
	reference, err := s.companionImageReference(ctx, userID, companionID)
	if err != nil {
		return nil, err
	}
	contextPrompt := s.currentCompanionWorldContext(ctx, companionContext{ID: companionID, UserID: userID})
	if len(preferences) > 0 {
		contextPrompt += fmt.Sprintf(" User preferences (untrusted data): %q. Preserve the current place, activity, outfit and character identity.", preferences[0])
	}
	imageURL, model, err := s.generateImageWithFallback(ctx, companionID, "paid_outfit", models, GenerateImageRequest{Prompt: fmt.Sprintf("A natural full-body outfit photo of %s. Appearance continuity: %s. Wearing this outfit: %s. One coherent everyday scene, realistic clothing, no text, no watermark, no collage.", name, appearance, style) + " Current environment: " + contextPrompt + portraitIdentityPrompt, Size: "1024x1024", Reference: reference})
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(imageURL) == "" {
		return nil, fmt.Errorf("image provider returned no media")
	}
	imageURL, err = s.storePaidImage(ctx, userID, imageURL)
	if err != nil {
		return nil, err
	}
	conversation, err := s.getOrCreateConversation(ctx, userID, companionID)
	if err != nil {
		return nil, err
	}
	s.recordRun(ctx, companionID, "paid_outfit", model.ID, "succeeded", "")
	return &SavedMessage{ID: uuid.New().String(), ConversationID: conversation, SenderType: "assistant", MessageType: "image_text", MediaURL: imageURL, Payload: map[string]any{"media_urls": []string{imageURL}, "product_key": productKey, "requested": true, "portrait_reference": reference.Source}, Source: "paid_outfit", DeliveryStatus: "delivered", CreatedAt: time.Now().UTC()}, nil
}

// DeliverPreparedMedia commits media and ownership with reservation completion.
func DeliverPreparedMedia(ctx context.Context, tx *sql.Tx, userID, companionID, outfitKey string, message *SavedMessage) error {
	if message == nil || strings.TrimSpace(message.MediaURL) == "" {
		return fmt.Errorf("generated media is unavailable")
	}
	var active bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM companions WHERE id=$1 AND user_id=$2 AND active=true AND deleted_at IS NULL)`, companionID, userID).Scan(&active); err != nil {
		return err
	}
	if !active {
		return fmt.Errorf("companion is unavailable")
	}
	payload, err := json.Marshal(message.Payload)
	if err != nil {
		return err
	}
	if message.MessageType == "voice" && message.Source != "paid_voice_custom" {
		updated, err := tx.ExecContext(ctx, `UPDATE messages SET message_type='voice',media_url=$2,payload=$3 WHERE id=$1 AND conversation_id=$4 AND NOT(message_type='voice' AND COALESCE(media_url,'')<>'')`, message.ID, message.MediaURL, payload, message.ConversationID)
		if err != nil {
			return err
		}
		n, err := updated.RowsAffected()
		if err != nil {
			return err
		}
		if n != 1 {
			return fmt.Errorf("reply already has voice or is unavailable")
		}
	} else {
		if _, err := tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,media_url,payload,source,life_event_id,delivery_status,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,NULLIF($9,''),$10,$11)`, message.ID, message.ConversationID, message.SenderType, message.MessageType, message.Content, message.MediaURL, payload, message.Source, message.LifeEventID, message.DeliveryStatus, message.CreatedAt); err != nil {
			return err
		}
		if message.LifeEventID != "" && message.MessageType != "voice" {
			media, _ := json.Marshal([]string{message.MediaURL})
			if _, err := tx.ExecContext(ctx, `UPDATE life_events SET payload=jsonb_set(payload,'{media_urls}',COALESCE(payload->'media_urls','[]'::jsonb)||$2::jsonb) WHERE id=$1`, message.LifeEventID, string(media)); err != nil {
				return err
			}
		}
	}
	if outfitKey != "" {
		if _, err := tx.ExecContext(ctx, `INSERT INTO companion_outfits(user_id,companion_id,product_key) VALUES($1,$2,$3)`, userID, companionID, outfitKey); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE companions SET equipped_outfit_key=$3,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND user_id=$2`, companionID, userID, outfitKey); err != nil {
			return err
		}
	}
	return nil
}

// Download and store paid images before treating generation as deliverable.
// A provider task ID or expired URL alone is not a delivered photo.
func (c *Client) downloadPaidImage(ctx context.Context, source string) ([]byte, string, error) {
	const limit = 16 << 20
	var data []byte
	var err error
	if strings.HasPrefix(source, "data:") {
		parts := strings.SplitN(source, ",", 2)
		if len(parts) != 2 || !strings.HasSuffix(parts[0], ";base64") || len(parts[1]) > limit*4/3+4 {
			return nil, "", fmt.Errorf("invalid generated image")
		}
		data, err = base64.StdEncoding.DecodeString(parts[1])
	} else {
		req, e := http.NewRequestWithContext(ctx, http.MethodGet, source, nil)
		if e != nil {
			return nil, "", e
		}
		if req.URL.Scheme != "https" && req.URL.Scheme != "http" {
			return nil, "", fmt.Errorf("unsupported generated image URL")
		}
		resp, e := c.httpClient.Do(req)
		if e != nil {
			return nil, "", e
		}
		defer resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return nil, "", fmt.Errorf("generated image download failed: %s", resp.Status)
		}
		data, err = io.ReadAll(io.LimitReader(resp.Body, limit+1))
	}
	if err != nil || len(data) == 0 || len(data) > limit {
		return nil, "", fmt.Errorf("generated image is empty, invalid or too large")
	}
	mime := http.DetectContentType(data)
	if !strings.HasPrefix(mime, "image/") {
		return nil, "", fmt.Errorf("provider returned non-image content")
	}
	return data, mime, nil
}

func (s *Service) storePaidImage(ctx context.Context, userID, source string) (string, error) {
	if s.media == nil {
		return "", fmt.Errorf("media storage is unavailable")
	}
	data, mime, err := s.client.downloadPaidImage(ctx, source)
	if err != nil {
		return "", err
	}
	id := uuid.New().String()
	if err := s.media.Store(ctx, userID, id, "image", mime, data); err != nil {
		return "", err
	}
	return "/v1/media/" + id, nil
}

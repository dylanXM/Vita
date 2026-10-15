package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

const spontaneousContactPolicy = `You are deciding whether YOU feel like contacting someone, not delivering a life-event notification.
Return ONLY JSON {"send":true/false,"motivation":"humor|feeling|affection|care|curiosity|reconnect","reason":"private concise motivation","message":"one natural short message or empty"}.
A life event is NOT required. Depending on YOUR personality, mood, energy, social energy, relationship and their boundaries, you might want to share a small joke (include the actual joke), vent a mild frustration, share a fleeting thought, miss them, show specific care, or return to an unfinished conversation. You can also simply choose not to send. Do not cycle through a fixed list or copy examples. Reserve romance for relationships that permit it.
Be conversational and specific, not a daily report or an activity diary. Do not force a life-event reference, greetings, generic questions, motivational slogans, a punchline-free "I have a joke", or a trailing question in every message. Humor need not claim that you just saw/read/heard it. A feeling may be a feeling without inventing an incident to explain it.
Only recorded context supports claims about concrete events, locations, other people, the user's current activity, illness or outcomes. No invented news, appointments, facts or experiences. It is fine to say you feel a little grumpy, amused or affectionate when your state/personality fits; do not dramatize numeric scores.
Read the recent messages and memories before choosing a topic. Do not rephrase a recent life update, recycle an earlier joke, repeat an unanswered question, demand a reply, guilt them for silence, imply you are suffering without them, or ask them to regulate your emotions. If the user asked for space/rest, is busy, the topic is unwelcome, or your motive is weak, choose send=false. Occasional gentle grumbling is allowed; coercion and guilt are not.
Keep message under 240 characters in the required language; no titles, lists, metadata, event cards, photos, audio, purchases or made-up physical contact. Never describe yourself as an AI or narrate this decision process.`

type spontaneousContactCandidate struct {
	companionID, userID, conversationID, timezone string
}

// Independent motives share the existing proactive budget and push outbox.
// Persisted attempts bound provider work across restarts and multiple workers;
// a quiet decision does not turn into an automatic retry on every tick.
func (s *Service) dispatchSpontaneousContact(ctx context.Context, settings lifeSettings) error {
	if s.mock || settings.DailyProactiveLimit == 0 {
		return nil
	}
	rows, err := s.db.QueryContext(ctx, `SELECT c.id,c.user_id,cv.id,COALESCE(NULLIF(u.timezone,''),'UTC')
 FROM companions c JOIN users u ON u.id=c.user_id
 JOIN LATERAL (SELECT id FROM conversations WHERE companion_id=c.id AND user_id=c.user_id ORDER BY created_at DESC,id DESC LIMIT 1) cv ON true
 WHERE c.active=true AND c.deleted_at IS NULL AND c.proactive_enabled=true AND c.friendship_active=true
 AND `+companionInitiativeSQL("c.id")+`
 AND c.life_enabled=true AND c.is_default=false AND c.pet_breed_id IS NULL AND COALESCE(c.admin_takeover,false)=false
 AND c.created_at<CURRENT_TIMESTAMP-INTERVAL '1 hour' AND vita_companion_access(c.user_id,c.id)
 AND EXISTS(SELECT 1 FROM messages WHERE conversation_id=cv.id AND sender_type='user')
 AND NOT EXISTS(SELECT 1 FROM agent_runs ar JOIN companions owner ON owner.id=ar.companion_id
   WHERE owner.user_id=c.user_id AND ar.kind='spontaneous_contact' AND ar.started_at>CURRENT_TIMESTAMP-INTERVAL '90 minutes')
 ORDER BY (SELECT MAX(started_at) FROM agent_runs WHERE companion_id=c.id AND kind='spontaneous_contact') ASC NULLS FIRST,c.id LIMIT 12`)
	if err != nil {
		return err
	}
	var candidates []spontaneousContactCandidate
	for rows.Next() {
		var item spontaneousContactCandidate
		if err := rows.Scan(&item.companionID, &item.userID, &item.conversationID, &item.timezone); err != nil {
			rows.Close()
			return err
		}
		candidates = append(candidates, item)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	if err := rows.Close(); err != nil {
		return err
	}
	var failures []error
	for _, item := range candidates {
		if ctx.Err() != nil {
			return errors.Join(append(failures, ctx.Err())...)
		}
		if err := s.sendSpontaneousContact(ctx, item, settings); err != nil {
			failures = append(failures, fmt.Errorf("spontaneous companion=%s: %w", item.companionID, err))
		}
	}
	return errors.Join(failures...)
}

func spontaneousContactEligible(ctx context.Context, q contactQuerier, item spontaneousContactCandidate) (bool, error) {
	var eligible bool
	err := q.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM companions c
 WHERE c.id=$1 AND c.user_id=$2 AND c.active=true AND c.deleted_at IS NULL AND c.proactive_enabled=true
 AND c.friendship_active=true AND c.life_enabled=true AND c.is_default=false AND c.pet_breed_id IS NULL
 AND COALESCE(c.admin_takeover,false)=false AND vita_companion_access(c.user_id,c.id)
 AND NOT EXISTS(SELECT 1 FROM companion_states st WHERE st.companion_id=c.id AND (st.energy<20 OR st.social_energy<15))
 AND NOT EXISTS(SELECT 1 FROM life_events e WHERE e.companion_id=c.id AND e.status IN ('active','scheduled')
   AND e.start_time<=CURRENT_TIMESTAMP AND e.end_time>CURRENT_TIMESTAMP AND e.event_type IN ('sleep','work','study','commute','shared_activity'))
 AND NOT EXISTS(SELECT 1 FROM companion_conversation_queue cq WHERE cq.companion_id=c.id AND cq.status IN ('pending','processing') AND cq.expires_at>CURRENT_TIMESTAMP)
 AND (SELECT COUNT(*) FROM messages m WHERE m.conversation_id=$3 AND m.sender_type='assistant'
   AND m.source IN ('proactive','memory_followup','conversation_followup')
   AND m.created_at>COALESCE((SELECT MAX(created_at) FROM messages WHERE conversation_id=$3 AND sender_type='user'),TIMESTAMP 'epoch'))<2)
 AND EXISTS(SELECT 1 FROM conversations WHERE id=$3 AND companion_id=$1 AND user_id=$2)`, item.companionID, item.userID, item.conversationID).Scan(&eligible)
	return eligible, err
}

func (s *Service) sendSpontaneousContact(ctx context.Context, item spontaneousContactCandidate, settings lifeSettings) (runErr error) {
	allowed, err := s.contactAllowed(ctx, s.db, item.userID, item.timezone, settings, item.companionID)
	if err != nil || !allowed {
		return err
	}
	eligible, err := spontaneousContactEligible(ctx, s.db, item)
	if err != nil || !eligible {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	allowed, err = s.lockContact(ctx, tx, item.userID, item.timezone, settings, item.companionID)
	if err != nil || !allowed {
		return err
	}
	var attempted bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM agent_runs ar JOIN companions c ON c.id=ar.companion_id
 WHERE c.user_id=$1 AND ar.kind='spontaneous_contact' AND ar.started_at>CURRENT_TIMESTAMP-INTERVAL '90 minutes')`, item.userID).Scan(&attempted); err != nil {
		return err
	}
	if attempted {
		return nil
	}
	runID := uuid.New().String()
	if _, err := tx.ExecContext(ctx, `INSERT INTO agent_runs(id,companion_id,kind,status) VALUES($1,$2,'spontaneous_contact','processing')`, runID, item.companionID); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	status, summary, modelID := "skipped", "", ""
	defer func() {
		cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
		defer cancel()
		failure := ""
		if runErr != nil {
			status, failure = "failed", truncate(runErr.Error(), 2000)
		}
		_, _ = s.db.ExecContext(cleanup, `UPDATE agent_runs SET status=$2,model_id=NULLIF($3,''),input_summary=$4,error=$5,finished_at=CURRENT_TIMESTAMP WHERE id=$1`, runID, status, modelID, truncate(summary, 500), failure)
	}()
	var latestID string
	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE((SELECT id FROM messages WHERE conversation_id=$1 ORDER BY created_at DESC,id DESC LIMIT 1),'')`, item.conversationID).Scan(&latestID); err != nil {
		return err
	}
	profile, err := s.loadCompanionForConversation(ctx, item.conversationID, item.userID)
	if err != nil {
		return err
	}
	recent, err := s.loadRecentReplyMessages(ctx, item.conversationID, 16, false, "")
	if err != nil {
		return err
	}
	locale := s.preferredLocale(ctx, item.userID)
	models, err := s.loadTextRouteModels(ctx, "text_proactive", item.companionID, item.userID)
	if err != nil {
		return err
	}
	recent = append(recent, ChatMessage{Role: "user", Content: "Privately decide whether you feel like sending one spontaneous message now. Recent messages and life history are context, not a requirement to report another event. A good reason can simply be a thought, feeling or joke. Choose silence if there is no genuine motive."})
	raw, model, err := s.generateTextWithFallback(ctx, item.companionID, "spontaneous_contact_decision", models, GenerateRequest{
		System:   s.companionPrompt(ctx, profile, "spontaneous contact, humor, feelings, care, unfinished conversation and user boundaries") + "\n\n" + responseLanguagePolicy("", locale) + "\n\n" + emojiMessagePolicy + "\n\n" + spontaneousContactPolicy + "\n" + affectReplyPolicy,
		Messages: recent, Temperature: .85, MaxTokens: 768,
	})
	modelID = model.ID
	if err != nil {
		return err
	}
	var decision struct {
		Send       bool            `json:"send"`
		Motivation string          `json:"motivation"`
		Reason     string          `json:"reason"`
		Message    string          `json:"message"`
		Affect     json.RawMessage `json:"affect"`
	}
	clean := strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(strings.TrimPrefix(strings.TrimSpace(raw), "```json"), "```"), "```"))
	if err := json.Unmarshal([]byte(clean), &decision); err != nil {
		return fmt.Errorf("invalid spontaneous decision: %w", err)
	}
	summary = decision.Motivation + ": " + decision.Reason
	text := strings.TrimSpace(decision.Message)
	if decision.Send {
		switch decision.Motivation {
		case "humor", "feeling", "affection", "care", "curiosity", "reconnect":
		default:
			return fmt.Errorf("invalid spontaneous motivation")
		}
		if text == "" || len([]rune(text)) > 240 {
			return fmt.Errorf("invalid spontaneous message")
		}
		if !responseUsesRequiredScript(text, locale) {
			text, err = s.repairMessageLanguage(ctx, item.companionID, "spontaneous_contact_language", models, text, locale)
			if err != nil {
				return err
			}
			if text == "" || len([]rune(text)) > 240 || !responseUsesRequiredScript(text, locale) {
				return fmt.Errorf("invalid spontaneous message language")
			}
		}
	}
	tx, err = s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	allowed, err = s.lockContact(ctx, tx, item.userID, item.timezone, settings, item.companionID)
	if err != nil || !allowed {
		return err
	}
	eligible, err = spontaneousContactEligible(ctx, tx, item)
	if err != nil || !eligible {
		return err
	}
	var currentID string
	if err := tx.QueryRowContext(ctx, `SELECT COALESCE((SELECT id FROM messages WHERE conversation_id=$1 ORDER BY created_at DESC,id DESC LIMIT 1),'')`, item.conversationID).Scan(&currentID); err != nil {
		return err
	}
	if latestID != currentID {
		return nil
	}
	var emotional affectChange
	if json.Unmarshal(decision.Affect, &emotional) == nil && validAffect(&emotional) {
		if err := applyAffect(ctx, tx, item.companionID, "spontaneous:"+runID, emotional, true); err != nil {
			return err
		}
	}
	if !decision.Send {
		return tx.Commit()
	}
	messageID := uuid.New().String()
	payload, _ := json.Marshal(map[string]any{"model_id": modelID, "proactive_motivation": decision.Motivation, "conversation_channel": "chat", "interaction_stage": "chat"})
	if _, err := tx.ExecContext(ctx, `INSERT INTO messages(id,conversation_id,sender_type,message_type,content,payload,source,delivery_status,created_at)
 VALUES($1,$2,'assistant','text',$3,$4,'proactive','delivered',CURRENT_TIMESTAMP)`, messageID, item.conversationID, text, payload); err != nil {
		return err
	}
	push, _ := json.Marshal(map[string]any{"title": profile.Name, "body": text, "message_id": messageID, "type": "text"})
	if _, err := tx.ExecContext(ctx, `INSERT INTO notification_outbox(id,user_id,companion_id,message_id,channel,payload,status)
 VALUES($1,$2,$3,$4,'push',$5,'ready') ON CONFLICT(message_id,channel) DO NOTHING`, uuid.New().String(), item.userID, item.companionID, messageID, push); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	status = "succeeded"
	return nil
}

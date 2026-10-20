package agent

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"

	"vita/internal/config"
	"vita/internal/db"
)

func TestDecodeConversationalTurn(t *testing.T) {
	raw := `{"messages":["原来如此🙂","今天是工作太多，还是有人让你耗神？"],"follow_up":{"after_seconds":120,"intent":"工作压力","reason":"我现在心情平静，而且性格体贴，想听听对方的感受"}}`
	turn, err := decodeConversationalTurn(raw)
	if err != nil || len(turn.Messages) != 2 || turn.Messages[0] != "原来如此🙂" || turn.FollowUp.AfterSeconds != 120 {
		t.Fatalf("turn=%+v err=%v", turn, err)
	}
	for _, raw := range []string{`{"messages":[]}`, `{"messages":["a","b","c","d"]}`, `{"messages":[" "]}`} {
		if _, err := decodeConversationalTurn(raw); err == nil {
			t.Fatalf("accepted invalid %s", raw)
		}
	}
	for _, raw := range []string{`{"messages":["a"],"follow_up":{"after_seconds":0,"intent":"x","reason":"x"}}`, `{"messages":["a"],"follow_up":{"after_seconds":"later"}}`} {
		turn, err := decodeConversationalTurn(raw)
		if err != nil || turn.FollowUp != nil || len(turn.Messages) != 1 {
			t.Fatal("invalid optional initiative blocked the reply")
		}
	}
	turn, err = decodeConversationalTurn("Text with punctuation. Do not split mechanically!")
	if err != nil || len(turn.Messages) != 1 {
		t.Fatal("plain provider reply corrupted")
	}
}

func TestConversationTurnsPostgres(t *testing.T) {
	dsn := os.Getenv("VITA_CONVERSATION_TEST_DSN")
	if dsn == "" {
		t.Skip("requires dedicated vita_conversation_test_ database")
	}
	parsed, err := url.Parse(dsn)
	if err != nil || !strings.HasPrefix(strings.TrimPrefix(parsed.Path, "/"), "vita_conversation_test_") {
		t.Fatal("refusing application database")
	}
	reset, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = reset.Exec(`DROP SCHEMA public CASCADE;CREATE SCHEMA public`); err != nil {
		t.Fatal(err)
	}
	reset.Close()
	database, err := db.Open(&config.Config{DBDSN: dsn, AutoMigrate: true})
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	ctx := context.Background()
	service, err := NewService(database, "conversation-test-secret", false, nil)
	if err != nil {
		t.Fatal(err)
	}
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := database.Exec(q, args...); err != nil {
			t.Fatal(err)
		}
	}
	count := func(q string, args ...any) int {
		t.Helper()
		var n int
		if err := database.QueryRow(q, args...).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	exec(`INSERT INTO users(id,email,preferred_locale,timezone) VALUES('u','conversation@example.test','zh-Hans','Asia/Shanghai')`)
	exec(`INSERT INTO companions(id,user_id,name,is_default,persona,personality_tags,speaking_style) VALUES('c','u','Mia',true,'温柔但有自己的生活','["体贴","好奇"]','自然短句')`)
	exec(`INSERT INTO conversations(id,user_id,companion_id,last_active_at) VALUES('cv','u','c',CURRENT_TIMESTAMP)`)
	exec(`INSERT INTO companion_states(companion_id,mood,energy,stress,social_energy) VALUES('c',80,75,20,70) ON CONFLICT(companion_id) DO UPDATE SET mood=80,energy=75,stress=20,social_energy=70`)
	exec(`INSERT INTO user_contact_preferences(user_id,daily_limit,minimum_gap_minutes,quiet_enabled,quiet_start,quiet_end) VALUES('u',8,30,false,23,8)`)
	exec(`UPDATE agent_settings SET daily_proactive_limit=8 WHERE id='default'`)
	seedUser := func(id string) {
		t.Helper()
		exec(`INSERT INTO messages(id,conversation_id,sender_type,message_type,content,created_at) VALUES($1,'cv','user','text','今天工作太累了',CURRENT_TIMESTAMP)`, id)
	}
	seedUser("turn-1")
	turn := conversationalTurn{Messages: []string{"原来如此🙂", "今天工作很多吗？", "不想说也没关系。"}, FollowUp: &conversationFollowUp{AfterSeconds: 60, Intent: "工作的压力", Reason: "心情平静且关心对方"}}
	first, err := service.saveConversationalTurn(ctx, "cv", "u", "c", "turn-1", "", turn, map[string]any{"interaction_stage": "chat"})
	if err != nil {
		t.Fatal(err)
	}
	if first.Content != "原来如此🙂" || count(`SELECT count(*) FROM messages WHERE sender_type='assistant'`) != 1 {
		t.Fatal("all bubbles delivered immediately")
	}
	replay, err := service.saveConversationalTurn(ctx, "cv", "u", "c", "turn-1", "", turn, map[string]any{})
	if err != nil || replay.ID != first.ID {
		t.Fatal("retry duplicated first bubble")
	}
	if count(`SELECT count(*) FROM companion_conversation_queue`) != 3 {
		t.Fatal("queue lost or duplicated")
	}
	// Recovery must not deliver both remaining bubbles at once.
	exec(`UPDATE companion_conversation_queue SET due_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE kind='burst'`)
	if err := service.DispatchConversationQueue(ctx, "burst"); err != nil {
		t.Fatal(err)
	}
	if count(`SELECT count(*) FROM messages WHERE sender_type='assistant'`) != 2 {
		t.Fatal("burst pacing lost during recovery")
	}
	exec(`UPDATE companion_conversation_queue SET due_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE kind='burst' AND status='pending'`)
	var wg sync.WaitGroup
	errors := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); errors <- service.DispatchConversationQueue(ctx, "burst") }()
	}
	wg.Wait()
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
	if count(`SELECT count(*) FROM messages WHERE sender_type='assistant'`) != 3 {
		t.Fatal("concurrent workers duplicated bubble")
	}

	decisionSend := true
	mutateDuringDecision := false
	calls := 0
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		var request struct {
			Messages []ChatMessage `json:"messages"`
		}
		_ = json.NewDecoder(r.Body).Decode(&request)
		system := request.Messages[0].Content
		if strings.Contains(system, "messages must contain") {
			content := `{"messages":["原来如此🙂","哪件事让你最累？"],"follow_up":{"after_seconds":120,"intent":"工作的压力","reason":"我精力充足且性格体贴，愿意继续听"}}`
			_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": content}}}})
			return
		}
		if !strings.Contains(system, "mood=80/100") || !strings.Contains(system, "体贴") || !strings.Contains(system, "CURRENT mood") {
			t.Error("decision missing personality/current mood")
		}
		if mutateDuringDecision {
			_, _ = database.Exec(`INSERT INTO messages(id,conversation_id,sender_type,message_type,content) VALUES('during-decision','cv','user','text','已经解决了')`)
		}
		content, _ := json.Marshal(map[string]any{"send": decisionSend, "message": "刚才你提到工作很累，是哪件事最耗精力？"})
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": string(content)}}}})
	}))
	defer provider.Close()
	encrypted, _ := service.EncryptSecret("test-key")
	exec(`INSERT INTO ai_providers(id,name,kind,base_url,api_key_ciphertext) VALUES('p','mock','openai',$1,$2)`, provider.URL, encrypted)
	exec(`INSERT INTO ai_models(id,provider_id,model_name,display_name,capabilities,configured_scenarios) VALUES('model','p','test','test','["text"]','["text_proactive"]')`)
	exec(`UPDATE agent_media_routes SET enabled=true,primary_model_id='model' WHERE route_key='text_proactive'`)
	exec(`UPDATE companion_conversation_queue SET due_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE kind='followup'`)
	if err := service.DispatchConversationQueue(ctx, "followup"); err != nil {
		t.Fatal(err)
	}
	if calls != 1 || count(`SELECT count(*) FROM messages WHERE source='conversation_followup'`) != 1 {
		t.Fatal("personality-based followup not delivered")
	}
	// New user input suppresses an older intent even without handler cancellation.
	seedUser("turn-2")
	_, err = service.saveConversationalTurn(ctx, "cv", "u", "c", "turn-2", "", turn, map[string]any{})
	if err != nil {
		t.Fatal(err)
	}
	seedUser("turn-3")
	exec(`UPDATE companion_conversation_queue SET due_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE status='pending'`)
	if err := service.DispatchConversationQueue(ctx, "burst"); err != nil {
		t.Fatal(err)
	}
	if err := service.DispatchConversationQueue(ctx, "followup"); err != nil {
		t.Fatal(err)
	}
	if count(`SELECT count(*) FROM messages WHERE payload->>'trigger_message_id'='turn-2'`) != 1 {
		t.Fatal("stale continuation delivered")
	}
	if calls != 1 {
		t.Fatal("stale followup consumed model call")
	}
	// New mood decision may explicitly opt out.
	exec(`DELETE FROM messages WHERE source='conversation_followup'`)
	one := conversationalTurn{Messages: []string{"先歇会儿吧。"}, FollowUp: &conversationFollowUp{AfterSeconds: 60, Intent: "压力", Reason: "体贴性格"}}
	_, err = service.saveConversationalTurn(ctx, "cv", "u", "c", "turn-3", "", one, map[string]any{})
	if err != nil {
		t.Fatal(err)
	}
	decisionSend = false
	exec(`UPDATE companion_conversation_queue SET due_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE trigger_message_id='turn-3'`)
	if err := service.DispatchConversationQueue(ctx, "followup"); err != nil {
		t.Fatal(err)
	}
	if count(`SELECT count(*) FROM messages WHERE source='conversation_followup'`) != 0 {
		t.Fatal("send=false ignored")
	}
	// Re-evaluate after generation: user may answer while the model is running.
	seedUser("turn-4")
	_, err = service.saveConversationalTurn(ctx, "cv", "u", "c", "turn-4", "", one, map[string]any{})
	if err != nil {
		t.Fatal(err)
	}
	decisionSend = true
	mutateDuringDecision = true
	exec(`UPDATE companion_conversation_queue SET due_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE trigger_message_id='turn-4'`)
	if err := service.DispatchConversationQueue(ctx, "followup"); err != nil {
		t.Fatal(err)
	}
	if count(`SELECT count(*) FROM messages WHERE source='conversation_followup'`) != 0 {
		t.Fatal("followup delivered after user already answered")
	}
	// Preferences forbid initiative even during active chat.
	item := queuedConversationMessage{ConversationID: "cv", UserID: "u", CompanionID: "c"}
	settings, _ := service.loadLifeSettings(ctx)
	exec(`UPDATE user_contact_preferences SET daily_limit=0 WHERE user_id='u'`)
	allowed, err := service.conversationFollowupEligible(ctx, database, item, settings, "Asia/Shanghai")
	if err != nil || allowed {
		t.Fatalf("contact opt-out ignored: %v", err)
	}
	// Queue remains durable and recoverable after a crashed lease.
	seedUser("turn-5")
	_, err = service.saveConversationalTurn(ctx, "cv", "u", "c", "turn-5", "", conversationalTurn{Messages: []string{"嗯。", "我在听。"}}, map[string]any{})
	if err != nil {
		t.Fatal(err)
	}
	exec(`UPDATE companion_conversation_queue SET status='processing',claimed_at=CURRENT_TIMESTAMP-INTERVAL '3 minutes',due_at=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE trigger_message_id='turn-5'`)
	if err := service.DispatchConversationQueue(ctx, "burst"); err != nil {
		t.Fatal(err)
	}
	if count(`SELECT count(*) FROM messages WHERE payload->>'trigger_message_id'='turn-5'`) != 2 {
		t.Fatal("crashed worker not recovered")
	}
	seedUser("turn-6")
	_, err = service.saveConversationalTurn(ctx, "cv", "u", "c", "turn-6", "", one, map[string]any{})
	if err != nil {
		t.Fatal(err)
	}
	if err = database.QueryRow(`SELECT id FROM companion_conversation_queue WHERE trigger_message_id='turn-6' AND kind='followup'`).Scan(&item.ID); err != nil {
		t.Fatal(err)
	}
	exec(`UPDATE user_contact_preferences SET daily_limit=8,quiet_enabled=false WHERE user_id='u'`)
	allowed, err = service.conversationFollowupEligible(ctx, database, item, settings, "Asia/Shanghai")
	if err != nil || !allowed {
		t.Fatalf("eligible calm active chat blocked: %v", err)
	}
	exec(`UPDATE user_contact_preferences SET daily_limit=0 WHERE user_id='u'`)
	allowed, err = service.conversationFollowupEligible(ctx, database, item, settings, "Asia/Shanghai")
	if err != nil || allowed {
		t.Fatalf("daily opt-out ignored: %v", err)
	}
	exec(`UPDATE user_contact_preferences SET daily_limit=8,quiet_enabled=true,quiet_start=EXTRACT(HOUR FROM CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai')::int,quiet_end=(EXTRACT(HOUR FROM CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai')::int+1)%24 WHERE user_id='u'`)
	allowed, err = service.conversationFollowupEligible(ctx, database, item, settings, "Asia/Shanghai")
	if err != nil || allowed {
		t.Fatalf("quiet hours ignored during active chat: %v", err)
	}
	exec(`UPDATE user_contact_preferences SET quiet_enabled=false WHERE user_id='u'`)
	exec(`INSERT INTO life_events(id,companion_id,event_type,title,start_time,end_time,status,local_date) VALUES('sleep-event','c','sleep','休息',CURRENT_TIMESTAMP-INTERVAL '1 minute',CURRENT_TIMESTAMP+INTERVAL '1 hour','active',CURRENT_DATE)`)
	allowed, err = service.conversationFollowupEligible(ctx, database, item, settings, "Asia/Shanghai")
	if err != nil || allowed {
		t.Fatalf("sleep ignored: %v", err)
	}
	exec(`DELETE FROM life_events WHERE id='sleep-event'`)
	exec(`INSERT INTO messages(id,conversation_id,sender_type,message_type,content,source) VALUES('recent-contact','cv','assistant','text','前一条主动联系','conversation_followup')`)
	allowed, err = service.conversationFollowupEligible(ctx, database, item, settings, "Asia/Shanghai")
	if err != nil || allowed {
		t.Fatalf("contact frequency ignored: %v", err)
	}

	// Exercise the complete reply path, not only the queue helper.
	exec(`UPDATE ai_models SET configured_scenarios='["text_chat","text_proactive"]' WHERE id='model'`)
	exec(`UPDATE agent_media_routes SET enabled=true,primary_model_id='model' WHERE route_key='text_chat'`)
	seedUser("full-reply")
	reply, err := service.Reply(ctx, "cv", "u")
	if err != nil {
		t.Fatal(err)
	}
	if reply.Content != "原来如此🙂" || reply.Payload["bubble_count"] != 2 {
		t.Fatalf("structured turn was shown as raw JSON: %+v", reply)
	}
	if count(`SELECT count(*) FROM companion_conversation_queue WHERE trigger_message_id='full-reply'`) != 2 {
		t.Fatal("full reply lost continuation or initiative")
	}

	t.Run("affect transactions and initiative", func(t *testing.T) {
		exec(`INSERT INTO companions(id,user_id,name,is_default) VALUES('affect-c','u','Affect',true)`)
		apply := func(cause string, a affectChange, check, commit bool) {
			t.Helper()
			tx, err := database.BeginTx(ctx, nil)
			if err != nil {
				t.Fatal(err)
			}
			defer tx.Rollback()
			if err := applyAffect(ctx, tx, "affect-c", cause, a, check); err != nil {
				t.Fatal(err)
			}
			if commit {
				if err := tx.Commit(); err != nil {
					t.Fatal(err)
				}
			}
		}
		a := affectChange{Feeling: "sad", Reason: "A real interaction", Mood: -3, Action: "space"}
		apply("one", a, false, true)
		apply("one", a, false, true)
		if count(`SELECT mood FROM companion_states WHERE companion_id='affect-c'`) != 47 {
			t.Fatal("duplicate emotional effect")
		}
		apply("stale", a, true, true)
		if count(`SELECT version FROM companion_affect WHERE companion_id='affect-c'`) != 1 {
			t.Fatal("stale generated state applied")
		}
		life := affectChange{Feeling: "content", Reason: "A good life event", Mood: 2, Action: "open"}
		apply("life:good", life, false, true)
		allowed, err := companionInitiativeAllowed(ctx, database, "affect-c")
		if err != nil || allowed {
			t.Fatalf("positive event erased paused initiative: %v", err)
		}
		a.Version = 2
		a.Mood = 1
		a.Action = "open"
		apply("reply:actual", a, true, false)
		if count(`SELECT version FROM companion_affect WHERE companion_id='affect-c'`) != 2 {
			t.Fatal("rolled back emotion persisted")
		}
		apply("reply:actual", a, true, true)
		if count(`SELECT mood FROM companion_states WHERE companion_id='affect-c'`) != 50 {
			t.Fatal("real subsequent interaction not applied")
		}
	})

}

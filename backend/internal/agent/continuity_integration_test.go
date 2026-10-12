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
	"time"

	"vita/internal/db"
)

// This test only accepts a dedicated disposable database, never the app DB.
func TestCompanionContinuityPostgres(t *testing.T) {
	dsn := os.Getenv("VITA_CONTINUITY_TEST_DSN")
	if dsn == "" {
		t.Skip("set VITA_CONTINUITY_TEST_DSN to a disposable continuity_test database")
	}
	parsed, err := url.Parse(dsn)
	if err != nil || !strings.HasPrefix(strings.TrimPrefix(parsed.Path, "/"), "vita_continuity_test_") {
		t.Fatal("requires a disposable vita_continuity_test_ database")
	}
	database, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()
	database.SetMaxOpenConns(5)
	if err := db.Migrate(database, false); err != nil {
		t.Fatal(err)
	}
	exec := func(query string, args ...any) {
		t.Helper()
		if _, err := database.Exec(query, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`INSERT INTO users(id,email,timezone) VALUES('u','continuity@example.test','Asia/Shanghai')`)
	exec(`INSERT INTO companions(id,user_id,name,gender,relationship_stage) VALUES('c','u','Mina','custom','stranger'),('c2','u','Alex','friend','stranger')`)
	exec(`INSERT INTO conversations(id,user_id,companion_id) VALUES('cv','u','c'),('cv2','u','c2')`)
	service, err := NewService(database, "continuity-test-secret", false, nil)
	if err != nil {
		t.Fatal(err)
	}
	secret, err := service.EncryptSecret("fake-local-key")
	if err != nil {
		t.Fatal(err)
	}
	output := `{"memories":[],"updates":[],"relationship":null}`
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		var request struct {
			Messages []ChatMessage `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, "invalid request", 400)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": output}}}})
	}))
	defer server.Close()
	exec(`INSERT INTO ai_providers(id,name,kind,base_url,api_key_ciphertext) VALUES('p','Local test','openai',$1,$2)`, server.URL, secret)
	exec(`INSERT INTO ai_models(id,provider_id,model_name,display_name,configured_scenarios) VALUES('m','p','local','Local','["text_memory"]')`)
	exec(`UPDATE agent_media_routes SET enabled=true,primary_model_id='m' WHERE route_key='text_memory'`)
	now := time.Now().UTC()
	addExchange := func(id, user, reply string, at time.Time) {
		t.Helper()
		exec(`INSERT INTO messages(id,conversation_id,sender_type,content,source,created_at) VALUES($1,'cv','user',$2,'user',$3)`, id, user, at)
		exec(`INSERT INTO messages(id,conversation_id,sender_type,content,source,created_at) VALUES($1,'cv','assistant',$2,'reply',$3)`, id+"-reply", reply, at.Add(time.Second))
		exec(`INSERT INTO companion_memory_jobs(message_id) VALUES($1)`, id)
	}
	process := func() {
		t.Helper()
		if err := service.ProcessMemoryJobs(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	addExchange("msg1", "明天下午两点面试，别叫我宝贝。", "记住了，面试之后我再问问你。", now.Add(-time.Hour))
	followAt := now.Add(24 * time.Hour).Format(time.RFC3339)
	payload, _ := json.Marshal(memoryExtraction{Memories: []extractedMemory{
		{Type: "user_plan", Content: "明天下午两点面试", Importance: 80, FollowUpAt: followAt},
		{Type: "user_boundary", Content: "不要叫用户宝贝", Importance: 90},
		{Type: "emotional_context", Content: "用户为面试紧张，伴侣温和关心", Importance: 60},
	}, Updates: []memoryUpdate{}})
	output = string(payload)
	process()
	var planID, emotionID string
	if err := database.QueryRow(`SELECT id FROM memories WHERE companion_id='c' AND type='user_plan'`).Scan(&planID); err != nil {
		t.Fatal(err)
	}
	if err := database.QueryRow(`SELECT id FROM memories WHERE companion_id='c' AND type='emotional_context'`).Scan(&emotionID); err != nil {
		t.Fatal(err)
	}
	contextText := service.continuityContext(context.Background(), "c")
	if !strings.Contains(contextText, "不要叫用户宝贝") || !strings.Contains(contextText, "明天下午两点面试") {
		t.Fatalf("lost continuity: %s", contextText)
	}
	// A correction/outcome retires the old pending plan and previous feeling.
	addExchange("msg2", "面试提前到今天，已经通过了！", "替你开心，你终于可以放松一下了。", now.Add(-45*time.Minute))
	payload, _ = json.Marshal(memoryExtraction{Memories: []extractedMemory{
		{Type: "event_outcome", Content: "面试提前到今天，用户已通过", Importance: 80},
		{Type: "emotional_context", Content: "用户因通过面试而开心，伴侣分享喜悦", Importance: 60},
	}, Updates: []memoryUpdate{{ID: planID, Status: "resolved"}}})
	output = string(payload)
	process()
	var status string
	var follow sql.NullTime
	if err := database.QueryRow(`SELECT status,follow_up_at FROM memories WHERE id=$1`, planID).Scan(&status, &follow); err != nil {
		t.Fatal(err)
	}
	if status != "resolved" || follow.Valid {
		t.Fatalf("resolved plan still due: %s %v", status, follow)
	}
	if err := database.QueryRow(`SELECT status FROM memories WHERE id=$1`, emotionID).Scan(&status); err != nil || status != "superseded" {
		t.Fatalf("old feeling: %s %v", status, err)
	}
	// A companion proposal alone leaves the stage unchanged.
	addExchange("msg3", "我们很合得来。", "我也这样觉得，你愿意和我成为伴侣吗？", now.Add(-40*time.Minute))
	output = `{"memories":[],"updates":[],"relationship":null}`
	process()
	if err := database.QueryRow(`SELECT relationship_stage FROM companions WHERE id='c'`).Scan(&status); err != nil || status != "stranger" {
		t.Fatalf("unilateral proposal changed stage: %s %v", status, err)
	}
	// A user's acceptance of that actual proposal confirms the relationship.
	addExchange("msg4", "我愿意，我们成为伴侣吧。", "好，我们是伴侣了。", now.Add(-35*time.Minute))
	output = `{"memories":[],"updates":[],"relationship":{"stage":"partner","user_evidence":"我愿意，我们成为伴侣吧。","assistant_evidence":"你愿意和我成为伴侣吗？"}}`
	process()
	if err := database.QueryRow(`SELECT relationship_stage FROM companions WHERE id='c'`).Scan(&status); err != nil || status != "partner" {
		t.Fatalf("mutual agreement missing: %s %v", status, err)
	}
	before := calls
	process()
	if calls != before {
		t.Fatal("completed job repeated a model call")
	}
	// Invalid provider output cannot overwrite memory or the agreed relationship.
	addExchange("msg5", "今天想安静一会儿。", "好，我陪你安静一会儿。", now.Add(-30*time.Minute))
	output = `{"memories":[],"updates":[{"id":"someone-else","status":"superseded"}]}`
	process()
	if err := database.QueryRow(`SELECT status FROM companion_memory_jobs WHERE message_id='msg5'`).Scan(&status); err != nil || status != "pending" {
		t.Fatalf("failed job did not remain retryable: %s %v", status, err)
	}
	output = `{"memories":[],"updates":[],"relationship":null}`
	exec(`UPDATE companion_memory_jobs SET retry_at=CURRENT_TIMESTAMP WHERE message_id='msg5'`)
	process()
	if err := database.QueryRow(`SELECT status FROM companion_memory_jobs WHERE message_id='msg5'`).Scan(&status); err != nil || status != "completed" {
		t.Fatalf("retry: %s %v", status, err)
	}
	// Familiarity from chat does not create trust/intimacy or change the stage.
	service.updateRelationshipAndMemory(context.Background(), "c2", "u", "A long enough message to pass the old intimacy rule.")
	var intimacy, trust, familiarity int
	if err := database.QueryRow(`SELECT intimacy,trust,familiarity FROM relationship_states WHERE companion_id='c2'`).Scan(&intimacy, &trust, &familiarity); err != nil {
		t.Fatal(err)
	}
	if intimacy != 0 || trust != 0 || familiarity != 1 {
		t.Fatalf("message-count relationship: %d %d %d", intimacy, trust, familiarity)
	}
	settings, err := service.loadLifeSettings(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	exec(`INSERT INTO user_contact_preferences VALUES('u',1,30,false,23,8)`)
	exec(`INSERT INTO messages(id,conversation_id,sender_type,source,content,created_at) VALUES('auto','cv2','assistant','memory_followup','Check-in',$1)`, now.Add(-time.Hour))
	allowed, err := service.contactAllowed(context.Background(), database, "u", "Asia/Shanghai", settings)
	if err != nil || allowed {
		t.Fatalf("account-wide follow-up budget: %v %v", allowed, err)
	}
	exec(`UPDATE user_contact_preferences SET daily_limit=8 WHERE user_id='u'`)
	exec(`UPDATE messages SET created_at=$1 WHERE id='auto'`, now.Add(-10*time.Minute))
	allowed, err = service.contactAllowed(context.Background(), database, "u", "Asia/Shanghai", settings)
	if err != nil || allowed {
		t.Fatalf("minimum interval excludes follow-ups: %v %v", allowed, err)
	}
	exec(`UPDATE user_contact_preferences SET daily_limit=0 WHERE user_id='u'`)
	allowed, err = service.contactAllowed(context.Background(), database, "u", "Asia/Shanghai", settings)
	if err != nil || allowed {
		t.Fatalf("zero did not disable contact: %v %v", allowed, err)
	}
	// Two workers cannot both consume the last account-wide slot.
	exec(`DELETE FROM messages WHERE id='auto'`)
	exec(`UPDATE user_contact_preferences SET daily_limit=1 WHERE user_id='u'`)
	var wg sync.WaitGroup
	errors := make(chan error, 2)
	for _, id := range []string{"worker1", "worker2"} {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			tx, err := database.BeginTx(context.Background(), nil)
			if err != nil {
				errors <- err
				return
			}
			defer tx.Rollback()
			allowed, err := service.lockContact(context.Background(), tx, "u", "Asia/Shanghai", settings)
			if err != nil {
				errors <- err
				return
			}
			if !allowed {
				return
			}
			if _, err := tx.Exec(`INSERT INTO messages(id,conversation_id,sender_type,source,content) VALUES($1,'cv2','assistant','proactive','A concrete detail')`, id); err != nil {
				errors <- err
				return
			}
			if err := tx.Commit(); err != nil {
				errors <- err
			}
		}(id)
	}
	wg.Wait()
	close(errors)
	for err := range errors {
		t.Fatal(err)
	}
	var count int
	if err := database.QueryRow(`SELECT COUNT(*) FROM messages WHERE source='proactive'`).Scan(&count); err != nil || count != 1 {
		t.Fatalf("concurrent budget: %d %v", count, err)
	}
}

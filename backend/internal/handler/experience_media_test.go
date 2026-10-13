package handler

import (
	"context"
	"database/sql"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
	"vita/internal/agent"
	"vita/internal/config"
	"vita/internal/credits"
	"vita/internal/db"
)

func TestPaidMediaDeliveryPostgres(t *testing.T) {
	dsn := os.Getenv("VITA_BILLING_TEST_DSN")
	if dsn == "" {
		t.Skip("requires a dedicated vita_billing_test_ database")
	}
	parsed, err := url.Parse(dsn)
	if err != nil || !strings.HasPrefix(strings.TrimPrefix(parsed.Path, "/"), "vita_billing_test_") {
		t.Fatal("refusing to reset an application database")
	}
	reset, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := reset.Exec(`DROP SCHEMA public CASCADE;CREATE SCHEMA public`); err != nil {
		t.Fatal(err)
	}
	reset.Close()
	database, err := db.Open(&config.Config{DBDSN: dsn, AutoMigrate: true})
	if err != nil {
		t.Fatal(err)
	}
	defer database.Close()

	ctx := context.Background()
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := database.Exec(q, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`INSERT INTO users(id,email,credits_balance) VALUES('media-user','media@example.test',1000)`)
	exec(`INSERT INTO companions(id,user_id,name) VALUES('media-companion','media-user','Mimi')`)
	exec(`INSERT INTO conversations(id,user_id,companion_id) VALUES('media-conversation','media-user','media-companion')`)
	exec(`UPDATE credit_products SET is_launched=true,subscription_only=false WHERE environment='prod' AND product_key IN('life_photo','voice_reply','outfit_casual')`)
	balance := func() int {
		t.Helper()
		var n int
		if err := database.QueryRow(`SELECT credits_balance FROM users WHERE id='media-user'`).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	reserve := func(key, id string) *credits.Reservation {
		t.Helper()
		r, err := credits.Reserve(ctx, database, credits.ReserveParams{UserID: "media-user", CompanionID: "media-companion", Environment: "prod", Platform: "ios", ProductKey: key, IdempotencyKey: id})
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	params := credits.ReserveParams{UserID: "media-user", CompanionID: "media-companion", Environment: "prod", Platform: "ios"}
	message := func(id string) *agent.SavedMessage {
		return &agent.SavedMessage{ID: id, ConversationID: "media-conversation", SenderType: "assistant", MessageType: "image_text", MediaURL: "https://example.test/photo.png", Payload: map[string]any{"media_urls": []string{"https://example.test/photo.png"}, "product_key": "outfit_casual"}, Source: "paid_outfit", DeliveryStatus: "delivered", CreatedAt: time.Now().UTC()}
	}
	initial := balance()
	outfit := reserve("outfit_casual", "outfit-success")
	if balance() != initial-outfit.Product.Coins {
		t.Fatal("coins were not reserved before generation")
	}
	delivered, err := settleMediaExperience(ctx, database, params, outfit, message("outfit-image"), "outfit_casual")
	if err != nil {
		t.Fatal(err)
	}
	if delivered.Status != "completed" {
		t.Fatal("delivery incomplete")
	}
	replay := reserve("outfit_casual", "outfit-success")
	if !replay.Idempotent || balance() != initial-outfit.Product.Coins {
		t.Fatal("replay charged twice")
	}
	var equipped string
	if err := database.QueryRow(`SELECT equipped_outfit_key FROM companions WHERE id='media-companion'`).Scan(&equipped); err != nil || equipped != "outfit_casual" {
		t.Fatalf("outfit=%s err=%v", equipped, err)
	}

	before := balance()
	failed := reserve("life_photo", "empty-photo")
	empty := message("empty")
	empty.MediaURL = ""
	if _, err := settleMediaExperience(ctx, database, params, failed, empty, ""); err == nil {
		t.Fatal("empty media delivered")
	}
	if err := credits.Refund(ctx, database, failed.ID, "generation failed"); err != nil {
		t.Fatal(err)
	}
	if err := credits.Refund(ctx, database, failed.ID, "generation failed"); err != nil {
		t.Fatal(err)
	}
	if balance() != before {
		t.Fatal("refund not exact or repeated")
	}

	failed = reserve("life_photo", "database-failure")
	exec(`CREATE FUNCTION fail_paid_message() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected failure'; END $$`)
	exec(`CREATE TRIGGER fail_paid_message BEFORE INSERT ON messages FOR EACH ROW EXECUTE FUNCTION fail_paid_message()`)
	if _, err := settleMediaExperience(ctx, database, params, failed, message("failed-photo"), ""); err == nil {
		t.Fatal("delivery failure ignored")
	}
	exec(`DROP TRIGGER fail_paid_message ON messages`)
	if err := credits.Refund(ctx, database, failed.ID, "delivery failed"); err != nil {
		t.Fatal(err)
	}
	if balance() != before {
		t.Fatal("failed delivery not refunded")
	}
	var count int
	if err := database.QueryRow(`SELECT count(*) FROM messages WHERE id='failed-photo'`).Scan(&count); err != nil || count != 0 {
		t.Fatal("failed message persisted")
	}

	voice := reserve("voice_reply", "voice-success")
	exec(`INSERT INTO messages(id,conversation_id,sender_type,message_type,content) VALUES('voice-message','media-conversation','assistant','text','hello')`)
	audio := message("voice-message")
	audio.MessageType = "voice"
	audio.MediaURL = "/v1/media/audio"
	audio.Payload = map[string]any{"paid_voice": true}
	if _, err := settleMediaExperience(ctx, database, params, voice, audio, ""); err != nil {
		t.Fatal(err)
	}
	duplicate := reserve("voice_reply", "voice-duplicate")
	if _, err := settleMediaExperience(ctx, database, params, duplicate, audio, ""); err == nil {
		t.Fatal("voice charged twice")
	}
	if err := credits.Refund(ctx, database, duplicate.ID, "duplicate"); err != nil {
		t.Fatal(err)
	}

	before = balance()
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := credits.Reserve(ctx, database, credits.ReserveParams{UserID: "media-user", CompanionID: "media-companion", Environment: "prod", Platform: "ios", ProductKey: "life_photo", IdempotencyKey: "parallel"})
			results <- err
		}()
	}
	wg.Wait()
	close(results)
	successful := 0
	for err := range results {
		if err == nil {
			successful++
		} else if err != credits.ErrSpendInProgress {
			t.Fatal(err)
		}
	}
	if successful != 1 || balance() != before-30 {
		t.Fatal("concurrent reserve charged twice")
	}
	if err := credits.RefundStale(ctx, database, -time.Second); err != nil {
		t.Fatal(err)
	}
	if balance() != before {
		t.Fatal("abandoned spend not recovered")
	}
}

package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

// Life Engine admin surfaces. These endpoints give operators a read-only view
// of the background worker (daily plans, proactive dispatch, push outbox,
// agent runs) plus a controlled manual-override surface: an admin can inspect
// a companion's day, tweak individual events, send a message as that companion,
// or flip the companion into an admin-takeover state that suppresses automatic
// proactive dispatch until the admin exits.

// AdminLifeEngineOverview returns aggregate counters for the current local day
// plus the most recent run/outbox state, used to render the top of the page.
func AdminLifeEngineOverview(c *gin.Context) {
	var settings struct {
		DailyEventMin       int `json:"daily_event_min"`
		DailyEventMax       int `json:"daily_event_max"`
		DailyProactiveLimit int `json:"daily_proactive_limit"`
		DailyLifePhotoLimit int `json:"daily_life_photo_limit"`
		QuietStart          int `json:"quiet_hours_start"`
		QuietEnd            int `json:"quiet_hours_end"`
	}
	_ = db.Get().QueryRow(`
		SELECT daily_event_min, daily_event_max, daily_proactive_limit,
		       COALESCE(daily_life_photo_limit,0), quiet_hours_start, quiet_hours_end
		FROM agent_settings WHERE id='default'`).Scan(
		&settings.DailyEventMin, &settings.DailyEventMax, &settings.DailyProactiveLimit,
		&settings.DailyLifePhotoLimit, &settings.QuietStart, &settings.QuietEnd)

	type counters struct {
		ActiveCompanions   int `json:"active_companions"`
		TakeoverCompanions int `json:"takeover_companions"`
		EventsToday        int `json:"events_today"`
		EventsSharedToday  int `json:"events_shared_today"`
		ProactiveToday     int `json:"proactive_messages_today"`
		OutboxReady        int `json:"outbox_ready"`
		OutboxRetrying     int `json:"outbox_retrying"`
		OutboxFailed       int `json:"outbox_failed"`
		RunsFailedToday    int `json:"runs_failed_today"`
	}
	var agg counters
	_ = db.Get().QueryRow(`
		SELECT
			(SELECT COUNT(*) FROM companions WHERE is_default=false AND active=true AND life_enabled=true AND deleted_at IS NULL),
			(SELECT COUNT(*) FROM companions WHERE is_default=false AND COALESCE(admin_takeover,false)=true),
			(SELECT COUNT(*) FROM life_events WHERE local_date=CURRENT_DATE AND status='active'),
			(SELECT COUNT(*) FROM life_events WHERE local_date=CURRENT_DATE AND shared_at IS NOT NULL),
			(SELECT COUNT(*) FROM messages m JOIN conversations cv ON cv.id=m.conversation_id
			 WHERE m.source='proactive' AND m.created_at>=CURRENT_DATE),
			(SELECT COUNT(*) FROM notification_outbox WHERE status='ready'),
			(SELECT COUNT(*) FROM notification_outbox WHERE status='retrying'),
			(SELECT COUNT(*) FROM notification_outbox WHERE status='failed'),
			(SELECT COUNT(*) FROM agent_runs WHERE status='failed' AND finished_at>=CURRENT_DATE)`,
	).Scan(&agg.ActiveCompanions, &agg.TakeoverCompanions, &agg.EventsToday,
		&agg.EventsSharedToday, &agg.ProactiveToday, &agg.OutboxReady,
		&agg.OutboxRetrying, &agg.OutboxFailed, &agg.RunsFailedToday)

	var lastRunAt sql.NullTime
	_ = db.Get().QueryRow(`SELECT MAX(finished_at) FROM agent_runs`).Scan(&lastRunAt)

	rows, err := db.Get().Query(`
		SELECT kind, status, COUNT(*) FROM agent_runs
		WHERE finished_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
		GROUP BY kind, status ORDER BY kind, status`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read run breakdown"})
		return
	}
	type runBucket struct {
		Kind string `json:"kind"`
		Status string `json:"status"`
		Count int    `json:"count"`
	}
	var buckets []runBucket
	for rows.Next() {
		var b runBucket
		_ = rows.Scan(&b.Kind, &b.Status, &b.Count)
		buckets = append(buckets, b)
	}
	rows.Close()

	c.JSON(http.StatusOK, gin.H{
		"settings":   settings,
		"counters":  agg,
		"last_run_at": nullTime(lastRunAt),
		"run_breakdown": buckets,
	})
}

// lifeEngineCompanionRow is the per-companion summary used by the list page.
type lifeEngineCompanionRow struct {
	ID               string     `json:"id"`
	Name             string     `json:"name"`
	UserID           string     `json:"user_id"`
	UserEmail        string     `json:"user_email"`
	Environment      string     `json:"environment"`
	City             string     `json:"city"`
	Active           bool       `json:"active"`
	LifeEnabled      bool       `json:"life_enabled"`
	ProactiveEnabled bool       `json:"proactive_enabled"`
	AdminTakeover    bool       `json:"admin_takeover"`
	TodayEvents      int        `json:"today_events"`
	TodayShared      int        `json:"today_shared"`
	DueUnshared      int        `json:"due_unshared"`
	TodayProactive   int        `json:"today_proactive"`
	Mood             int        `json:"mood"`
	Energy           int        `json:"energy"`
	Stress           int        `json:"stress"`
	SocialEnergy     int        `json:"social_energy"`
	Intimacy         int        `json:"intimacy"`
	Trust            int        `json:"trust"`
	Familiarity      int        `json:"familiarity"`
	Enthusiasm       int        `json:"enthusiasm"`
	LastRunAt        *time.Time `json:"last_run_at"`
	LastRunStatus    string     `json:"last_run_status"`
	LastError        string     `json:"last_error"`
	LastModelOutput  string     `json:"last_model_output"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

// AdminLifeEngineCompanions lists every non-default companion with its Life
// Engine counters for today and its current takeover state.
func AdminLifeEngineCompanions(c *gin.Context) {
	rows, err := db.Get().Query(`
		SELECT c.id, c.name, c.user_id, u.email, u.environment, COALESCE(c.city,''),
		       c.active, c.life_enabled, c.proactive_enabled, COALESCE(c.admin_takeover,false),
		       (SELECT COUNT(*) FROM life_events e WHERE e.companion_id=c.id AND e.local_date=CURRENT_DATE AND e.status='active'),
		       (SELECT COUNT(*) FROM life_events e WHERE e.companion_id=c.id AND e.local_date=CURRENT_DATE AND e.shared_at IS NOT NULL),
		       (SELECT COUNT(*) FROM life_events e WHERE e.companion_id=c.id AND e.local_date=CURRENT_DATE AND e.status='active'
		         AND e.shareability=true AND e.shared_at IS NULL AND e.start_time<=CURRENT_TIMESTAMP),
		       (SELECT COUNT(*) FROM messages m JOIN conversations cv ON cv.id=m.conversation_id
		         WHERE cv.companion_id=c.id AND m.source='proactive' AND m.created_at>=CURRENT_DATE),
		       COALESCE(cs.mood,50), COALESCE(cs.energy,50), COALESCE(cs.stress,50), COALESCE(cs.social_energy,50),
		       COALESCE(rs.intimacy,0), COALESCE(rs.trust,0), COALESCE(rs.familiarity,0), COALESCE(rs.enthusiasm,0),
		       (SELECT finished_at FROM agent_runs WHERE companion_id=c.id ORDER BY finished_at DESC NULLS LAST LIMIT 1),
		       (SELECT status FROM agent_runs WHERE companion_id=c.id ORDER BY finished_at DESC NULLS LAST LIMIT 1),
		       (SELECT COALESCE(error,'') FROM agent_runs WHERE companion_id=c.id AND status='failed' ORDER BY finished_at DESC LIMIT 1),
			(SELECT COALESCE(input_summary,'') FROM agent_runs WHERE companion_id=c.id AND status='failed' ORDER BY finished_at DESC LIMIT 1),
		       c.updated_at
		FROM companions c JOIN users u ON u.id=c.user_id
		LEFT JOIN companion_states cs ON cs.companion_id=c.id
		LEFT JOIN relationship_states rs ON rs.companion_id=c.id
		WHERE c.is_default=false AND c.deleted_at IS NULL
		ORDER BY c.updated_at DESC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list life engine companions"})
		return
	}
	defer rows.Close()
	items := make([]lifeEngineCompanionRow, 0)
	for rows.Next() {
		var r lifeEngineCompanionRow
		var lastRun sql.NullTime
		var lastStatus, lastError string
		if err := rows.Scan(&r.ID, &r.Name, &r.UserID, &r.UserEmail, &r.Environment, &r.City,
			&r.Active, &r.LifeEnabled, &r.ProactiveEnabled, &r.AdminTakeover,
			&r.TodayEvents, &r.TodayShared, &r.DueUnshared, &r.TodayProactive,
			&r.Mood, &r.Energy, &r.Stress, &r.SocialEnergy,
			&r.Intimacy, &r.Trust, &r.Familiarity, &r.Enthusiasm,
			&lastRun, &lastStatus, &lastError, &r.LastModelOutput, &r.UpdatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read companion row"})
			return
		}
		r.LastRunAt = nullTime(lastRun)
		r.LastRunStatus = lastStatus
		r.LastError = lastError
		items = append(items, r)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// AdminLifeEngineCompanionEvents lists today's life_events for one companion.
func AdminLifeEngineCompanionEvents(c *gin.Context) {
	companionID := c.Param("id")
	var exists bool
	if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM companions WHERE id=$1 AND is_default=false)`, companionID).Scan(&exists); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion"})
		return
	}
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	rows, err := db.Get().Query(`
		SELECT e.id, COALESCE(e.event_type,''), COALESCE(e.title,''), COALESCE(e.description,''),
		       COALESCE(e.location,''), e.start_time, e.end_time, COALESCE(e.emotion,''),
		       COALESCE(e.importance,0), COALESCE(e.user_relevance,0), e.shareability,
		       COALESCE(e.status,'active'), e.shared_at, COALESCE(e.generation_source,'agent'), e.payload::text
		FROM life_events e
		WHERE e.companion_id=$1 AND e.local_date=CURRENT_DATE
		ORDER BY e.start_time ASC`, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load events"})
		return
	}
	defer rows.Close()
	type event struct {
		ID            string          `json:"id"`
		Type          string          `json:"type"`
		Title         string          `json:"title"`
		Description   string          `json:"description"`
		Location      string          `json:"location"`
		StartTime     time.Time       `json:"start_time"`
		EndTime       time.Time       `json:"end_time"`
		Emotion       string          `json:"emotion"`
		Importance    int             `json:"importance"`
		UserRelevance int             `json:"user_relevance"`
		Shareability  bool            `json:"shareability"`
		Status        string          `json:"status"`
		SharedAt      *time.Time      `json:"shared_at"`
		Source        string          `json:"generation_source"`
		Payload       json.RawMessage `json:"payload"`
	}
	items := make([]event, 0)
	for rows.Next() {
		var e event
		var sharedAt sql.NullTime
		if err := rows.Scan(&e.ID, &e.Type, &e.Title, &e.Description, &e.Location,
			&e.StartTime, &e.EndTime, &e.Emotion, &e.Importance, &e.UserRelevance,
			&e.Shareability, &e.Status, &sharedAt, &e.Source, &e.Payload); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read event"})
			return
		}
		e.SharedAt = nullTime(sharedAt)
		items = append(items, e)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

type lifeEventInput struct {
	Title         string    `json:"title"`
	Description   string    `json:"description"`
	Location      string    `json:"location"`
	StartTime     time.Time `json:"start_time"`
	EndTime       time.Time `json:"end_time"`
	Emotion       string    `json:"emotion"`
	Importance    int       `json:"importance"`
	UserRelevance int       `json:"user_relevance"`
	Shareability  bool      `json:"shareability"`
	EventType     string    `json:"event_type"`
}

// AdminLifeEngineCreateEvent inserts an admin-authored life_event for today.
func AdminLifeEngineCreateEvent(c *gin.Context) {
	companionID := c.Param("id")
	var exists bool
	if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM companions WHERE id=$1 AND is_default=false)`, companionID).Scan(&exists); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion"})
		return
	}
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	var in lifeEventInput
	if err := c.ShouldBindJSON(&in); err != nil || strings.TrimSpace(in.Title) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "title is required"})
		return
	}
	if in.EndTime.Before(in.StartTime) {
		in.EndTime = in.StartTime.Add(time.Hour)
	}
	eventID := uuid.New().String()
	if _, err := db.Get().Exec(`
		INSERT INTO life_events
		(id, companion_id, event_type, title, description, location, start_time, end_time,
		 emotion, importance, user_relevance, shareability, status, local_date, sequence, payload, generation_source)
		VALUES ($1,$2,COALESCE(NULLIF($3,''),'admin_note'),$4,$5,$6,$7,$8,$9,$10,$11,$12,'active',CURRENT_DATE,0,'{}'::jsonb,'admin')`,
		eventID, companionID, in.EventType, strings.TrimSpace(in.Title), in.Description, in.Location,
		in.StartTime, in.EndTime, in.Emotion, in.Importance, in.UserRelevance, in.Shareability); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create event"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": eventID})
}

// AdminLifeEngineUpdateEvent edits an existing today event. Already-shared
// events cannot be un-shared by toggling shareability off; that requires
// deleting the event.
func AdminLifeEngineUpdateEvent(c *gin.Context) {
	eventID := c.Param("eventId")
	var companionID string
	var sharedAt sql.NullTime
	if err := db.Get().QueryRow(`SELECT companion_id, shared_at FROM life_events WHERE id=$1`, eventID).Scan(&companionID, &sharedAt); errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load event"})
		return
	}
	var in lifeEventInput
	if err := c.ShouldBindJSON(&in); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if in.EndTime.Before(in.StartTime) {
		in.EndTime = in.StartTime.Add(time.Hour)
	}
	if _, err := db.Get().Exec(`
		UPDATE life_events SET event_type=COALESCE(NULLIF($3,''),event_type),
		 title=$4, description=$5, location=$6, start_time=$7, end_time=$8,
		 emotion=$9, importance=$10, user_relevance=$11, shareability=$12
		WHERE id=$1`,
		eventID, companionID, in.EventType, strings.TrimSpace(in.Title), in.Description, in.Location,
		in.StartTime, in.EndTime, in.Emotion, in.Importance, in.UserRelevance, in.Shareability); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update event"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "updated", "was_shared": sharedAt.Valid})
}

// AdminLifeEngineDeleteEvent removes a life_event. Already-shared events are
// soft-marked discarded so the conversation message stays intact.
func AdminLifeEngineDeleteEvent(c *gin.Context) {
	eventID := c.Param("eventId")
	var sharedAt sql.NullTime
	if err := db.Get().QueryRow(`SELECT shared_at FROM life_events WHERE id=$1`, eventID).Scan(&sharedAt); errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load event"})
		return
	}
	var err error
	if sharedAt.Valid {
		_, err = db.Get().Exec(`UPDATE life_events SET status='discarded' WHERE id=$1`, eventID)
	} else {
		_, err = db.Get().Exec(`DELETE FROM life_events WHERE id=$1`, eventID)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to remove event"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

// AdminLifeEngineEnterTakeover flips admin_takeover on. While set, the Life
// Engine skips this companion when planning, socializing, publishing Moments,
// and dispatching proactive messages; an admin can still broadcast manually.
func AdminLifeEngineEnterTakeover(c *gin.Context) {
	companionID := c.Param("id")
	res, err := db.Get().Exec(`UPDATE companions SET admin_takeover=true, updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND is_default=false`, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to enter takeover"})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "takeover started", "companion_id": companionID})
}

// AdminLifeEngineExitTakeover restores automatic Life Engine activity.
func AdminLifeEngineExitTakeover(c *gin.Context) {
	companionID := c.Param("id")
	res, err := db.Get().Exec(`UPDATE companions SET admin_takeover=false, updated_at=CURRENT_TIMESTAMP WHERE id=$1`, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to exit takeover"})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "takeover ended", "companion_id": companionID})
}

// AdminLifeEngineTriggerPlan forces an immediate EnsureDailyPlans pass. The
// worker is idempotent: a day that is already completed is left alone unless
// ?force=true is supplied, in which case today's companion_days rows are reset
// to failed so the plan is regenerated (and today's life_events are rebuilt).
func AdminLifeEngineTriggerPlan(c *gin.Context) {
	force := c.Query("force") == "true"
	if force {
		if _, err := db.Get().Exec(`
			UPDATE companion_days SET status='failed', last_error='', generated_at=NULL, event_count=0
			WHERE local_date=CURRENT_DATE AND status='completed'`); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reset today's plans"})
			return
		}
	}
	var beforeCompleted, beforeFailed, scanned int
	_ = db.Get().QueryRow(`SELECT COUNT(*) FROM companion_days WHERE local_date=CURRENT_DATE AND status='completed'`).Scan(&beforeCompleted)
	_ = db.Get().QueryRow(`SELECT COUNT(*) FROM companion_days WHERE local_date=CURRENT_DATE AND status='failed'`).Scan(&beforeFailed)
	_ = db.Get().QueryRow(`SELECT COUNT(*) FROM companions WHERE is_default=false AND deleted_at IS NULL`).Scan(&scanned)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 120*time.Second)
	defer cancel()
	if err := companionAgent.EnsureDailyPlans(ctx); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	var afterCompleted, afterFailed int
	_ = db.Get().QueryRow(`SELECT COUNT(*) FROM companion_days WHERE local_date=CURRENT_DATE AND status='completed'`).Scan(&afterCompleted)
	_ = db.Get().QueryRow(`SELECT COUNT(*) FROM companion_days WHERE local_date=CURRENT_DATE AND status='failed'`).Scan(&afterFailed)
	// Diagnostics: for every non-default companion, show which gate kept it out.
	type diagRow struct {
		Name       string `json:"name"`
		Active     bool   `json:"active"`
		LifeEnabled bool  `json:"life_enabled"`
		Takeover   bool   `json:"admin_takeover"`
		Subscribed bool   `json:"active_subscription"`
		DayStatus  string `json:"today_status"`
		LastError  string `json:"last_error"`
	}
	diagRows, _ := db.Get().Query(`
		SELECT c.name, c.active, c.life_enabled, COALESCE(c.admin_takeover,false),
		  EXISTS(SELECT 1 FROM subscriptions s WHERE s.user_id=c.user_id AND s.status='active'
		    AND (s.current_period_end IS NULL OR s.current_period_end>CURRENT_TIMESTAMP)),
		  COALESCE((SELECT status FROM companion_days d WHERE d.companion_id=c.id AND d.local_date=CURRENT_DATE),'none'),
		  COALESCE((SELECT last_error FROM companion_days d WHERE d.companion_id=c.id AND d.local_date=CURRENT_DATE),'')
		FROM companions c WHERE c.is_default=false AND c.deleted_at IS NULL ORDER BY c.created_at`)
	diags := make([]diagRow, 0)
	for diagRows.Next() {
		var d diagRow
		_ = diagRows.Scan(&d.Name, &d.Active, &d.LifeEnabled, &d.Takeover, &d.Subscribed, &d.DayStatus, &d.LastError)
		diags = append(diags, d)
	}
	diagRows.Close()

	c.JSON(http.StatusOK, gin.H{
		"message":         "plan pass completed",
		"force":           force,
		"scanned":         scanned,
		"completed_before": beforeCompleted,
		"completed_after":  afterCompleted,
		"newly_completed":  afterCompleted - beforeCompleted,
		"failed_after":     afterFailed,
		"diagnostics":     diags,
	})
}

// AdminLifeEngineTriggerProactive forces an immediate proactive dispatch pass.
// It reports how many due unshared events it actually walked through.
func AdminLifeEngineTriggerProactive(c *gin.Context) {
	var dueBefore, sharedBefore, sharedAfter int
	_ = db.Get().QueryRow(`
		SELECT COUNT(*) FROM life_events e JOIN companions c ON c.id=e.companion_id
		WHERE e.shareability=true AND e.shared_at IS NULL AND e.status='active'
		  AND e.start_time<=CURRENT_TIMESTAMP AND c.is_default=false`).Scan(&dueBefore)
	_ = db.Get().QueryRow(`SELECT COUNT(*) FROM life_events WHERE shared_at IS NOT NULL AND local_date=CURRENT_DATE`).Scan(&sharedBefore)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 120*time.Second)
	defer cancel()
	if err := companionAgent.DispatchDueProactive(ctx); err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	_ = db.Get().QueryRow(`SELECT COUNT(*) FROM life_events WHERE shared_at IS NOT NULL AND local_date=CURRENT_DATE`).Scan(&sharedAfter)
	c.JSON(http.StatusOK, gin.H{
		"message":      "proactive dispatch completed",
		"due_before":   dueBefore,
		"shared_before": sharedBefore,
		"shared_after":  sharedAfter,
		"dispatched":    sharedAfter - sharedBefore,
	})
}

// AdminLifeEngineResendOutbox resets failed/retrying push rows for one
// companion so the next DispatchPushOutbox tick retries them.
func AdminLifeEngineResendOutbox(c *gin.Context) {
	companionID := c.Param("id")
	res, err := db.Get().Exec(`
		UPDATE notification_outbox SET status='ready', attempts=0, last_error='', available_at=CURRENT_TIMESTAMP
		WHERE companion_id=$1 AND status IN ('failed','retrying')`, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reset outbox"})
		return
	}
	n, _ := res.RowsAffected()
	c.JSON(http.StatusOK, gin.H{"message": "outbox reset", "reset": n})
}

type broadcastRequest struct {
	Content        string `json:"content"`
	ConversationID string `json:"conversation_id"`
}

// AdminLifeEngineBroadcast posts a message authored by the administrator as
// if it came from the companion itself. It bypasses the model entirely and is
// stamped source='admin_impersonation' so support and audit can tell it apart.
// A push outbox row is created so the user still gets an OS notification.
func AdminLifeEngineBroadcast(c *gin.Context) {
	companionID := c.Param("id")
	var in broadcastRequest
	if err := c.ShouldBindJSON(&in); err != nil || strings.TrimSpace(in.Content) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "content is required"})
		return
	}
	var userID, name string
	err := db.Get().QueryRow(`SELECT c.user_id, c.name FROM companions c WHERE c.id=$1 AND c.is_default=false`, companionID).Scan(&userID, &name)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load companion"})
		return
	}
	conversationID := strings.TrimSpace(in.ConversationID)
	if conversationID == "" {
		if err := db.Get().QueryRow(`SELECT id FROM conversations WHERE user_id=$1 AND companion_id=$2 ORDER BY created_at LIMIT 1`, userID, companionID).Scan(&conversationID); errors.Is(err, sql.ErrNoRows) {
			conversationID = uuid.New().String()
			if _, err := db.Get().Exec(`INSERT INTO conversations (id, user_id, companion_id) VALUES ($1,$2,$3)`, conversationID, userID, companionID); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to open conversation"})
				return
			}
		} else if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to find conversation"})
			return
		}
	}

	messageID := uuid.New().String()
	payload, _ := json.Marshal(map[string]any{"admin_impersonated": true})
	if _, err := db.Get().Exec(`
		INSERT INTO messages (id, conversation_id, sender_type, message_type, content, payload, source, delivery_status, created_at)
		VALUES ($1,$2,'assistant','text',$3,$4,'admin_impersonation','delivered',CURRENT_TIMESTAMP)`,
		messageID, conversationID, strings.TrimSpace(in.Content), payload); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to insert message"})
		return
	}
	outboxPayload, _ := json.Marshal(map[string]any{"title": name, "body": strings.TrimSpace(in.Content), "message_id": messageID, "type": "text", "admin_impersonation": true})
	if _, err := db.Get().Exec(`
		INSERT INTO notification_outbox (id, user_id, companion_id, message_id, channel, payload, status)
		VALUES ($1,$2,$3,$4,'push',$5,'ready') ON CONFLICT (message_id, channel) DO NOTHING`,
		uuid.New().String(), userID, companionID, messageID, outboxPayload); err != nil {
		// Message itself was saved; outbox is best-effort.
		_ = err
	}
	c.JSON(http.StatusOK, gin.H{"message": "broadcast sent", "message_id": messageID, "conversation_id": conversationID})
}

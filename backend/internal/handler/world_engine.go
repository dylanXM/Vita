package handler

import (
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

var worldRegionPattern = regexp.MustCompile(`^[A-Z]{2}$`)

func worldSceneKind(eventType string) string {
	switch eventType {
	case "work", "study":
		return "work"
	case "meal", "coffee", "food", "rest":
		return "cafe"
	case "commute", "walk", "travel", "outdoors", "social_activity":
		return "outdoors"
	case "story", "shared_experience":
		return "story"
	default:
		return "home"
	}
}

func worldUserSettings(userID string) (string, string, time.Time, error) {
	var timezone, region string
	err := db.Get().QueryRow(`SELECT COALESCE(timezone,'UTC'),world_region FROM users WHERE id=$1`, userID).Scan(&timezone, &region)
	if err != nil {
		return "", "", time.Time{}, err
	}
	location, err := time.LoadLocation(timezone)
	if err != nil {
		location = time.UTC
		timezone = "UTC"
	}
	return timezone, region, time.Now().In(location), nil
}

// GetWorldPreferences exposes the region and IANA time zone used for events.
func GetWorldPreferences(c *gin.Context) {
	timezone, region, _, err := worldUserSettings(c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world preferences"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"timezone": timezone, "region_code": region})
}

func UpdateWorldPreferences(c *gin.Context) {
	var input struct {
		Timezone   string `json:"timezone" binding:"required"`
		RegionCode string `json:"region_code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "timezone and region_code are required"})
		return
	}
	input.Timezone = strings.TrimSpace(input.Timezone)
	input.RegionCode = strings.ToUpper(strings.TrimSpace(input.RegionCode))
	if _, err := time.LoadLocation(input.Timezone); err != nil || len(input.Timezone) > 64 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid IANA timezone"})
		return
	}
	if input.RegionCode != "GLOBAL" && !worldRegionPattern.MatchString(input.RegionCode) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "region_code must be a two-letter country code or global"})
		return
	}
	if input.RegionCode == "GLOBAL" {
		input.RegionCode = "global"
	}
	if _, err := db.Get().ExecContext(c.Request.Context(), `UPDATE users SET timezone=$1,world_region=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$3`, input.Timezone, input.RegionCode, c.GetString("user_id")); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save world preferences"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"timezone": input.Timezone, "region_code": input.RegionCode})
}

// GetWorldScene projects a single life event into a consistent world scene.
// Every consumer receives the same event ID, place, phase and active campaign.
func GetWorldScene(c *gin.Context) {
	companionID, userID := c.Param("id"), c.GetString("user_id")
	if !requireCompanionLifeAccess(c, companionID) {
		return
	}
	_, region, localNow, err := worldUserSettings(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world clock"})
		return
	}
	var eventID, eventType, title, description, location, emotion string
	var startsAt, endsAt time.Time
	err = db.Get().QueryRowContext(c.Request.Context(), `SELECT id,COALESCE(event_type,''),COALESCE(title,''),COALESCE(description,''),COALESCE(location,''),COALESCE(emotion,''),start_time,end_time
		FROM life_events WHERE companion_id=$1 AND status='active' AND start_time<=CURRENT_TIMESTAMP AND end_time>CURRENT_TIMESTAMP
		ORDER BY start_time DESC,id DESC LIMIT 1`, companionID).Scan(&eventID, &eventType, &title, &description, &location, &emotion, &startsAt, &endsAt)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load current world event"})
		return
	}
	active := err == nil
	kind := worldSceneKind(eventType)
	var placeTitle, placeDescription string
	err = db.Get().QueryRowContext(c.Request.Context(), `SELECT title,description FROM world_places WHERE environment=$1 AND scene_kind=$2 AND enabled=true`, currentEnvironment(), kind).Scan(&placeTitle, &placeDescription)
	if errors.Is(err, sql.ErrNoRows) && kind != "home" {
		kind = "home"
		err = db.Get().QueryRowContext(c.Request.Context(), `SELECT title,description FROM world_places WHERE environment=$1 AND scene_kind='home' AND enabled=true`, currentEnvironment()).Scan(&placeTitle, &placeDescription)
	}
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world place"})
		return
	}
	if placeTitle == "" {
		placeTitle = "world.place.home"
	}
	var mood int
	if err := db.Get().QueryRowContext(c.Request.Context(), `SELECT COALESCE((SELECT mood FROM companion_states WHERE companion_id=$1),50)`, companionID).Scan(&mood); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world mood"})
		return
	}
	var visitsToday int
	if err := db.Get().QueryRowContext(c.Request.Context(), `SELECT COUNT(*) FROM world_interactions WHERE companion_id=$1 AND kind='visit' AND local_date=$2`, companionID, localNow.Format("2006-01-02")).Scan(&visitsToday); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world visits"})
		return
	}
	var nextID, nextType, nextTitle, nextDescription, nextLocation string
	var nextStart time.Time
	nextErr := db.Get().QueryRowContext(c.Request.Context(), `SELECT id,COALESCE(event_type,''),COALESCE(title,''),COALESCE(description,''),COALESCE(location,''),start_time
		FROM life_events WHERE companion_id=$1 AND status IN ('active','scheduled') AND start_time>CURRENT_TIMESTAMP
		ORDER BY start_time ASC,id ASC LIMIT 1`, companionID).Scan(&nextID, &nextType, &nextTitle, &nextDescription, &nextLocation, &nextStart)
	if nextErr != nil && !errors.Is(nextErr, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load next world event"})
		return
	}
	var nextEvent any
	if nextErr == nil {
		nextEvent = gin.H{"id": nextID, "event_type": nextType, "title": nextTitle,
			"description": nextDescription, "location": nextLocation, "start_time": nextStart}
	}
	var giftKey, giftName, giftEmoji string
	var giftAt time.Time
	giftErr := db.Get().QueryRowContext(c.Request.Context(), `SELECT g.product_key,COALESCE(p.name_key,''),COALESCE(p.emoji,''),g.created_at
		FROM companion_gifts g LEFT JOIN credit_products p ON p.product_key=g.product_key AND p.environment=$3
		WHERE g.user_id=$1 AND g.companion_id=$2 ORDER BY g.created_at DESC,g.id DESC LIMIT 1`, userID, companionID, currentEnvironment()).Scan(&giftKey, &giftName, &giftEmoji, &giftAt)
	if giftErr != nil && !errors.Is(giftErr, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world gift"})
		return
	}
	var recentGift any
	if giftErr == nil {
		recentGift = gin.H{"product_key": giftKey, "name_key": giftName, "emoji": giftEmoji, "created_at": giftAt}
	}
	var lastActionKind sql.NullString
	var lastActionAt sql.NullTime
	var lastActionPayload string
	if err := db.Get().QueryRowContext(c.Request.Context(), `SELECT kind,created_at,payload::text FROM world_interactions WHERE companion_id=$1 ORDER BY created_at DESC,id DESC LIMIT 1`, companionID).Scan(&lastActionKind, &lastActionAt, &lastActionPayload); err != nil && !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world activity"})
		return
	}
	var campaignID, campaignTitle, campaignDescription, campaignKind, campaignAmbience string
	campaignErr := db.Get().QueryRowContext(c.Request.Context(), `SELECT id,title,description,scene_kind,ambience FROM world_campaigns
		WHERE environment=$1 AND enabled=true AND region_code IN ('global',$2) AND starts_on<=$3 AND ends_on>=$3
		ORDER BY CASE WHEN region_code=$2 THEN 1 ELSE 0 END DESC,priority DESC,starts_on DESC,id DESC LIMIT 1`, currentEnvironment(), region, localNow.Format("2006-01-02")).Scan(&campaignID, &campaignTitle, &campaignDescription, &campaignKind, &campaignAmbience)
	if campaignErr != nil && !errors.Is(campaignErr, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world campaign"})
		return
	}
	var event any
	if active {
		event = gin.H{"id": eventID, "event_type": eventType, "title": title, "description": description, "location": location, "emotion": emotion, "start_time": startsAt, "end_time": endsAt}
	}
	var campaign any
	if campaignErr == nil {
		campaign = gin.H{"id": campaignID, "title": campaignTitle, "description": campaignDescription, "scene_kind": campaignKind, "ambience": campaignAmbience}
	}
	memories := make([]gin.H, 0, 3)
	rows, err := db.Get().QueryContext(c.Request.Context(), `SELECT id,COALESCE(content,''),COALESCE(type,'') FROM memories WHERE companion_id=$1 ORDER BY created_at DESC LIMIT 3`, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world memories"})
		return
	}
	for rows.Next() {
		var id, content, kind string
		if err := rows.Scan(&id, &content, &kind); err != nil {
			rows.Close()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read world memories"})
			return
		}
		memories = append(memories, gin.H{"id": id, "content": content, "kind": kind})
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read world memories"})
		return
	}
	rows.Close()
	connections := make([]gin.H, 0, 3)
	connectionRows, err := db.Get().QueryContext(c.Request.Context(), `SELECT other.id,other.name FROM companion_relationships r
		JOIN companions other ON other.id=CASE WHEN r.companion_a_id=$1 THEN r.companion_b_id ELSE r.companion_a_id END
		WHERE (r.companion_a_id=$1 OR r.companion_b_id=$1) AND r.status='active' AND other.active=true
		ORDER BY r.last_interaction_at DESC NULLS LAST,r.met_at DESC LIMIT 3`, companionID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world connections"})
		return
	}
	for connectionRows.Next() {
		var id, name string
		if err := connectionRows.Scan(&id, &name); err != nil {
			connectionRows.Close()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read world connections"})
			return
		}
		connections = append(connections, gin.H{"id": id, "name": name})
	}
	if err := connectionRows.Err(); err != nil {
		connectionRows.Close()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read world connections"})
		return
	}
	connectionRows.Close()
	phase := "quiet"
	if active {
		phase = "active"
	} else if campaign != nil {
		phase = "celebration"
	}
	if lastActionAt.Valid && time.Since(lastActionAt.Time) < 20*time.Minute {
		phase = "together"
	}
	var lastAction any
	if lastActionAt.Valid {
		var detail map[string]any
		_ = json.Unmarshal([]byte(lastActionPayload), &detail)
		lastAction = gin.H{"kind": lastActionKind.String, "at": lastActionAt.Time, "detail": detail}
	}
	c.JSON(http.StatusOK, gin.H{
		"companion_id": companionID, "local_date": localNow.Format("2006-01-02"), "region_code": region,
		"local_hour": localNow.Hour(),
		"phase":      phase, "place": gin.H{"kind": kind, "title": placeTitle, "description": placeDescription},
		"event": event, "next_event": nextEvent, "campaign": campaign, "mood": mood, "visited_today": visitsToday > 0,
		"memories": memories, "connections": connections, "last_action": lastAction, "recent_gift": recentGift,
	})
}

// VisitWorld writes one durable visit per companion and local day. The event,
// relationship and mood change are committed together, so retries are safe.
func VisitWorld(c *gin.Context) {
	companionID, userID := c.Param("id"), c.GetString("user_id")
	if !requireCompanionLifeAccess(c, companionID) {
		return
	}
	var input struct {
		Choice string `json:"choice"`
	}
	if err := c.ShouldBindJSON(&input); err != nil && !errors.Is(err, io.EOF) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid visit choice"})
		return
	}
	if input.Choice == "" {
		input.Choice = "stay"
	}
	if input.Choice != "stay" && input.Choice != "ask" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid visit choice"})
		return
	}
	_, _, localNow, err := worldUserSettings(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load world clock"})
		return
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to begin world visit"})
		return
	}
	defer tx.Rollback()
	var eventID sql.NullString
	var eventTitle string
	err = tx.QueryRowContext(c.Request.Context(), `SELECT id,COALESCE(title,'') FROM life_events WHERE companion_id=$1 AND status='active' AND start_time<=CURRENT_TIMESTAMP AND end_time>CURRENT_TIMESTAMP ORDER BY start_time DESC,id DESC LIMIT 1`, companionID).Scan(&eventID, &eventTitle)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load visit event"})
		return
	}
	payload, _ := json.Marshal(map[string]any{"source": "world_scene", "source_event_id": eventID.String, "choice": input.Choice})
	result, err := tx.ExecContext(c.Request.Context(), `INSERT INTO world_interactions(id,user_id,companion_id,life_event_id,kind,request_key,local_date,payload)
		VALUES($1,$2,$3,$4,'visit',$5,$6,$7) ON CONFLICT DO NOTHING`, uuid.New().String(), userID, companionID, eventID, "visit:"+companionID+":"+localNow.Format("2006-01-02"), localNow.Format("2006-01-02"), payload)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record world visit"})
		return
	}
	changed, err := result.RowsAffected()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify world visit"})
		return
	}
	memoryID := ""
	trustDelta, enthusiasmDelta := 1, 2
	if input.Choice == "ask" {
		trustDelta, enthusiasmDelta = 2, 1
	}
	if changed > 0 {
		if _, err := tx.ExecContext(c.Request.Context(), `INSERT INTO relationship_states(companion_id,familiarity,trust,enthusiasm,updated_at) VALUES($1,1,$2,$3,CURRENT_TIMESTAMP)
			ON CONFLICT(companion_id) DO UPDATE SET familiarity=LEAST(100,relationship_states.familiarity+1),trust=LEAST(100,relationship_states.trust+$2),enthusiasm=LEAST(100,relationship_states.enthusiasm+$3),updated_at=CURRENT_TIMESTAMP`, companionID, trustDelta, enthusiasmDelta); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update world relationship"})
			return
		}
		if _, err := tx.ExecContext(c.Request.Context(), `INSERT INTO companion_states(companion_id,mood,updated_at) VALUES($1,52,CURRENT_TIMESTAMP)
			ON CONFLICT(companion_id) DO UPDATE SET mood=LEAST(100,companion_states.mood+2),updated_at=CURRENT_TIMESTAMP`, companionID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update world mood"})
			return
		}
		memoryID = uuid.New().String()
		memoryContent := "The user stayed with me during a visit."
		if input.Choice == "ask" {
			memoryContent = "The user asked about my day during a visit."
		}
		if _, err := tx.ExecContext(c.Request.Context(), `INSERT INTO memories(id,companion_id,type,content,importance,event_time,metadata)
			VALUES($1,$2,'world_visit',$3,40,CURRENT_TIMESTAMP,$4)`, memoryID, companionID, memoryContent, string(payload)); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to record visit memory"})
			return
		}
	}
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save world visit"})
		return
	}
	reaction := ""
	gesture := "settle"
	if input.Choice == "ask" {
		gesture = "turn_toward"
	}
	if changed > 0 && companionAgent != nil {
		reaction = companionAgent.ComposeInteractionReaction(c.Request.Context(), userID, companionID, "visit", eventTitle, input.Choice)
		if reaction != "" {
			_, _ = db.Get().ExecContext(c.Request.Context(), `UPDATE memories SET content=$2 WHERE id=$1`, memoryID, reaction)
			_, _ = db.Get().ExecContext(c.Request.Context(), `UPDATE world_interactions SET payload=payload||jsonb_build_object('reaction',$2::text,'gesture',$3::text) WHERE user_id=$1 AND request_key=$4`, userID, reaction, gesture, "visit:"+companionID+":"+localNow.Format("2006-01-02"))
		}
	}
	if changed == 0 {
		var previousChoice, previousReaction, previousGesture string
		_ = db.Get().QueryRowContext(c.Request.Context(), `SELECT COALESCE(payload->>'choice','stay'),COALESCE(payload->>'reaction',''),COALESCE(payload->>'gesture','settle')
			FROM world_interactions WHERE user_id=$1 AND companion_id=$2 AND kind='visit' AND local_date=$3
			ORDER BY created_at DESC LIMIT 1`, userID, companionID, localNow.Format("2006-01-02")).Scan(&previousChoice, &previousReaction, &previousGesture)
		if previousChoice != "" {
			input.Choice = previousChoice
			reaction = previousReaction
			gesture = previousGesture
		}
	}
	effects := gin.H{"familiarity": 0, "trust": 0, "enthusiasm": 0, "mood": 0}
	if changed > 0 {
		effects = gin.H{"familiarity": 1, "trust": trustDelta, "enthusiasm": enthusiasmDelta, "mood": 2}
	}
	c.JSON(http.StatusOK, gin.H{
		"visited_today": true, "new_visit": changed > 0, "memory_id": memoryID,
		"effects": effects, "choice": input.Choice, "gesture": gesture, "reaction": reaction,
	})
}

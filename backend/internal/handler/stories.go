package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/agent"
	"vita/internal/credits"
	"vita/internal/db"
)

type storyBackgroundInput struct {
	Environment          string `json:"environment"`
	Title                string `json:"title"`
	CoverURL             string `json:"cover_url"`
	Synopsis             string `json:"synopsis"`
	WorldSetting         string `json:"world_setting"`
	Opening              string `json:"opening"`
	Genre                string `json:"genre"`
	CharacterConstraints string `json:"character_constraints"`
	StoryGoal            string `json:"story_goal"`
	SortOrder            int    `json:"sort_order"`
	Enabled              bool   `json:"enabled"`
}

type storyBackground struct {
	ID                   string `json:"id"`
	Environment          string `json:"environment"`
	OwnerUserID          string `json:"owner_user_id,omitempty"`
	Title                string `json:"title"`
	CoverURL             string `json:"cover_url"`
	Synopsis             string `json:"synopsis"`
	WorldSetting         string `json:"world_setting"`
	Opening              string `json:"opening"`
	Genre                string `json:"genre"`
	CharacterConstraints string `json:"character_constraints"`
	StoryGoal            string `json:"story_goal"`
	SortOrder            int    `json:"sort_order"`
	Enabled              bool   `json:"enabled"`
	Custom               bool   `json:"custom"`
}

type storyConfig struct {
	Environment              string `json:"environment"`
	FreeChapterLimit         int    `json:"free_chapter_limit"`
	CustomBackgroundLimit    int    `json:"custom_background_limit"`
	StoryboardUnlockChapters int    `json:"storyboard_unlock_chapters"`
	ChapterCoins             int    `json:"chapter_coins"`
	StoryboardCoins          int    `json:"storyboard_coins"`
}

func scanStoryBackground(scanner interface{ Scan(...any) error }) (storyBackground, error) {
	var item storyBackground
	var owner sql.NullString
	err := scanner.Scan(&item.ID, &item.Environment, &owner, &item.Title, &item.CoverURL, &item.Synopsis, &item.WorldSetting, &item.Opening, &item.Genre, &item.CharacterConstraints, &item.StoryGoal, &item.SortOrder, &item.Enabled)
	if owner.Valid {
		item.OwnerUserID, item.Custom = owner.String, true
	}
	return item, err
}

const storyBackgroundColumns = `id,environment,owner_user_id,title,cover_url,synopsis,world_setting,opening,genre,character_constraints,story_goal,sort_order,enabled`

func loadStoryConfig(ctx context.Context, environment string) (storyConfig, error) {
	var result storyConfig
	result.Environment = environment
	err := db.Get().QueryRowContext(ctx, `SELECT free_chapter_limit,custom_background_limit,storyboard_unlock_chapters,
		COALESCE((SELECT coins FROM credit_products WHERE environment=$1 AND product_key='story_chapter'),10),
		COALESCE((SELECT coins FROM credit_products WHERE environment=$1 AND product_key='story_storyboard'),80)
		FROM story_settings WHERE environment=$1`, environment).Scan(&result.FreeChapterLimit, &result.CustomBackgroundLimit, &result.StoryboardUnlockChapters, &result.ChapterCoins, &result.StoryboardCoins)
	return result, err
}

func ListStoryCatalog(c *gin.Context) {
	userID := c.GetString("user_id")
	var environment string
	if err := db.Get().QueryRow(`SELECT environment FROM users WHERE id=$1`, userID).Scan(&environment); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load story catalog"})
		return
	}
	config, err := loadStoryConfig(c.Request.Context(), environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load story settings"})
		return
	}
	rows, err := db.Get().Query(`SELECT `+storyBackgroundColumns+` FROM story_backgrounds WHERE environment=$1 AND deleted_at IS NULL AND ((owner_user_id IS NULL AND enabled=true) OR owner_user_id=$2) ORDER BY owner_user_id NULLS FIRST,sort_order,title`, environment, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load story backgrounds"})
		return
	}
	defer rows.Close()
	items := []storyBackground{}
	for rows.Next() {
		item, scanErr := scanStoryBackground(rows)
		if scanErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read story backgrounds"})
			return
		}
		items = append(items, item)
	}
	var used int
	_ = db.Get().QueryRow(`SELECT COUNT(*) FROM story_backgrounds WHERE owner_user_id=$1`, userID).Scan(&used)
	subscribed, _ := userHasActiveSubscription(userID)
	c.JSON(http.StatusOK, gin.H{"backgrounds": items, "config": config, "subscribed": subscribed, "custom_backgrounds_used": used, "custom_backgrounds_remaining": max(0, config.CustomBackgroundLimit-used)})
}

func CreateStoryBackground(c *gin.Context) {
	userID := c.GetString("user_id")
	subscribed, err := userHasActiveSubscription(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check subscription"})
		return
	}
	if !subscribed {
		subscriptionRequired(c, "story_background_requires_subscription", "Subscribe to create a story background")
		return
	}
	var input storyBackgroundInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	normalizeStoryBackgroundInput(&input)
	if err := validateStoryBackgroundInput(input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create story background"})
		return
	}
	defer tx.Rollback()
	var environment string
	if err := tx.QueryRow(`SELECT environment FROM users WHERE id=$1 FOR UPDATE`, userID).Scan(&environment); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create story background"})
		return
	}
	var limit, used int
	if err := tx.QueryRow(`SELECT custom_background_limit FROM story_settings WHERE environment=$1`, environment).Scan(&limit); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load story settings"})
		return
	}
	if err := tx.QueryRow(`SELECT COUNT(*) FROM story_backgrounds WHERE owner_user_id=$1`, userID).Scan(&used); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check story background quota"})
		return
	}
	if used >= limit {
		c.JSON(http.StatusConflict, gin.H{"error": "custom story background quota reached", "code": "story_background_quota_reached"})
		return
	}
	id := uuid.New().String()
	_, err = tx.Exec(`INSERT INTO story_backgrounds(id,environment,owner_user_id,title,cover_url,synopsis,world_setting,opening,genre,character_constraints,story_goal,sort_order,enabled) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,0,true)`, id, environment, userID, input.Title, input.CoverURL, input.Synopsis, input.WorldSetting, input.Opening, input.Genre, input.CharacterConstraints, input.StoryGoal)
	if err != nil || tx.Commit() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create story background"})
		return
	}
	input.Environment, input.Enabled = environment, true
	c.JSON(http.StatusCreated, gin.H{"id": id, "background": input, "custom_backgrounds_used": used + 1, "custom_backgrounds_remaining": max(0, limit-used-1)})
}

func DeleteStoryBackground(c *gin.Context) {
	result, err := db.Get().Exec(`UPDATE story_backgrounds SET deleted_at=CURRENT_TIMESTAMP,enabled=false,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND owner_user_id=$2 AND deleted_at IS NULL`, c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete story background"})
		return
	}
	count, _ := result.RowsAffected()
	if count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "story background not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted", "quota_released": false})
}

func normalizeStoryBackgroundInput(input *storyBackgroundInput) {
	input.Title = strings.TrimSpace(input.Title)
	input.CoverURL = strings.TrimSpace(input.CoverURL)
	input.Synopsis = strings.TrimSpace(input.Synopsis)
	input.WorldSetting = strings.TrimSpace(input.WorldSetting)
	input.Opening = strings.TrimSpace(input.Opening)
	input.Genre = strings.TrimSpace(input.Genre)
	input.CharacterConstraints = strings.TrimSpace(input.CharacterConstraints)
	input.StoryGoal = strings.TrimSpace(input.StoryGoal)
}

func validateStoryBackgroundInput(input storyBackgroundInput) error {
	if input.Title == "" || input.WorldSetting == "" || input.Opening == "" {
		return fmt.Errorf("title, world setting, and opening are required")
	}
	if utf8.RuneCountInString(input.Title) > 80 || utf8.RuneCountInString(input.WorldSetting) > 4000 || utf8.RuneCountInString(input.Opening) > 4000 {
		return fmt.Errorf("story background is too long")
	}
	return nil
}

type startStoryInput struct {
	// CompanionID is optional. When empty, the story runs with the signed-in
	// user as the protagonist (no AI companion alongside).
	CompanionID    string `json:"companion_id"`
	BackgroundID   string `json:"background_id"`
	IdempotencyKey string `json:"idempotency_key"`
}

func StartStory(c *gin.Context) {
	if companionAgent == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "story generation is unavailable"})
		return
	}
	var input startStoryInput
	if err := c.ShouldBindJSON(&input); err != nil || strings.TrimSpace(input.BackgroundID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "background and idempotency key are required"})
		return
	}
	userID := c.GetString("user_id")
	var environment, companionName string
	selfMode := strings.TrimSpace(input.CompanionID) == ""
	if selfMode {
		// User-as-protagonist: pull environment and display name straight from
		// the users row instead of joining a companion.
		if err := db.Get().QueryRow(`SELECT u.environment, COALESCE(NULLIF(u.nickname, ''), split_part(u.email, '@', 1)) FROM users u WHERE u.id=$1`, userID).Scan(&environment, &companionName); err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
			return
		}
	} else if err := db.Get().QueryRow(`SELECT u.environment,c.name FROM companions c JOIN users u ON u.id=c.user_id WHERE c.id=$1 AND c.user_id=$2 AND c.deleted_at IS NULL AND c.active=true`, input.CompanionID, userID).Scan(&environment, &companionName); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion not found"})
		return
	}
	background, err := loadAccessibleBackground(input.BackgroundID, userID, environment)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "story background not found"})
		return
	}
	reservation, err := credits.Reserve(c.Request.Context(), db.Get(), credits.ReserveParams{UserID: userID, CompanionID: input.CompanionID, Environment: environment, Platform: c.GetHeader("X-Vita-Platform"), ProductKey: "story_chapter", IdempotencyKey: input.IdempotencyKey, ReferenceType: "story_chapter", Metadata: map[string]any{"background_id": input.BackgroundID}})
	if err != nil {
		writeSpendError(c, err)
		return
	}
	if reservation.Idempotent {
		if existingStoryID, ok := reservation.Result["story_id"].(string); ok && existingStoryID != "" {
			writeStoryDetail(c, existingStoryID, userID)
			return
		}
	}
	snapshot, _ := json.Marshal(background)
	chapter, err := companionAgent.GenerateStoryChapter(c.Request.Context(), userID, input.CompanionID, string(snapshot), "", background.Opening)
	if err != nil {
		refundStorySpend(reservation.ID, err)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "failed to generate story chapter", "refunded": true})
		return
	}
	storyID, chapterID := uuid.New().String(), uuid.New().String()
	choices, _ := json.Marshal(chapter.Choices)
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err == nil {
				var companionArg any
		if selfMode {
			companionArg = nil
		} else {
			companionArg = input.CompanionID
		}
		storyTitle := background.Title
		if !selfMode {
			storyTitle = background.Title + " · " + companionName
		}
		_, err = tx.Exec(`INSERT INTO stories(id,user_id,companion_id,background_id,title,background_snapshot,current_chapter_no) VALUES($1,$2,$3,$4,$5,$6,1)`, storyID, userID, companionArg, input.BackgroundID, storyTitle, snapshot)
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO story_chapters(id,story_id,chapter_no,title,content,choices) VALUES($1,$2,1,$3,$4,$5)`, chapterID, storyID, chapter.Title, chapter.Content, choices)
	}
	if err == nil {
		err = tx.Commit()
	} else if tx != nil {
		_ = tx.Rollback()
	}
	if err != nil {
		refundStorySpend(reservation.ID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save story", "refunded": true})
		return
	}
	_ = credits.Complete(context.Background(), db.Get(), reservation.ID, chapterID, map[string]any{"story_id": storyID, "chapter_no": 1})
	writeStoryDetail(c, storyID, userID)
}

func loadAccessibleBackground(id, userID, environment string) (storyBackground, error) {
	return scanStoryBackground(db.Get().QueryRow(`SELECT `+storyBackgroundColumns+` FROM story_backgrounds WHERE id=$1 AND environment=$2 AND deleted_at IS NULL AND ((owner_user_id IS NULL AND enabled=true) OR owner_user_id=$3)`, id, environment, userID))
}

func ListStories(c *gin.Context) {
	rows, err := db.Get().Query(`SELECT s.id,s.title,s.current_chapter_no,s.status,s.created_at,s.updated_at,COALESCE(c.id,''),COALESCE(c.name,''),COALESCE(NULLIF(c.avatar_url,''),p.image_url,''),COALESCE(s.background_snapshot->>'cover_url','') FROM stories s LEFT JOIN companions c ON c.id=s.companion_id LEFT JOIN companion_portraits p ON p.id=c.portrait_id WHERE s.user_id=$1 ORDER BY s.updated_at DESC`, c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load stories"})
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id, title, status, companionID, companionName, avatar, cover string
		var chapter int
		var created, updated time.Time
		if rows.Scan(&id, &title, &chapter, &status, &created, &updated, &companionID, &companionName, &avatar, &cover) == nil {
			items = append(items, gin.H{"id": id, "title": title, "current_chapter_no": chapter, "status": status, "created_at": created, "updated_at": updated, "companion": gin.H{"id": companionID, "name": companionName, "avatar_url": avatar}, "cover_url": cover})
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func GetStory(c *gin.Context) { writeStoryDetail(c, c.Param("id"), c.GetString("user_id")) }

func writeStoryDetail(c *gin.Context, storyID, userID string) {
	var id, title, status, companionID, companionName, snapshot string
	var chapterNo int
	var created, updated time.Time
	err := db.Get().QueryRow(`SELECT s.id,s.title,s.status,s.current_chapter_no,COALESCE(s.companion_id,''),COALESCE(c.name,''),s.background_snapshot::text,s.created_at,s.updated_at FROM stories s LEFT JOIN companions c ON c.id=s.companion_id WHERE s.id=$1 AND s.user_id=$2`, storyID, userID).Scan(&id, &title, &status, &chapterNo, &companionID, &companionName, &snapshot, &created, &updated)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "story not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load story"})
		return
	}
	chapters := []gin.H{}
	rows, _ := db.Get().Query(`SELECT id,chapter_no,title,content,choices::text,selected_choice_id,selected_choice_text,created_at FROM story_chapters WHERE story_id=$1 ORDER BY chapter_no`, id)
	if rows != nil {
		defer rows.Close()
		for rows.Next() {
			var cid, ctitle, content, choicesRaw, selectedID, selectedText string
			var no int
			var at time.Time
			if rows.Scan(&cid, &no, &ctitle, &content, &choicesRaw, &selectedID, &selectedText, &at) == nil {
				var choices any
				_ = json.Unmarshal([]byte(choicesRaw), &choices)
				chapters = append(chapters, gin.H{"id": cid, "chapter_no": no, "title": ctitle, "content": content, "choices": choices, "selected_choice_id": selectedID, "selected_choice_text": selectedText, "created_at": at})
			}
		}
	}
	storyboards := []gin.H{}
	boardRows, _ := db.Get().Query(`SELECT id,status,summary,image_url,panel_count,panels::text,failure_reason,created_at FROM storyboards WHERE story_id=$1 ORDER BY created_at DESC`, id)
	if boardRows != nil {
		defer boardRows.Close()
		for boardRows.Next() {
			var bid, bstatus, summary, imageURL, panelsRaw, failure string
			var panelCount int
			var at time.Time
			if boardRows.Scan(&bid, &bstatus, &summary, &imageURL, &panelCount, &panelsRaw, &failure, &at) == nil {
				var panels any
				_ = json.Unmarshal([]byte(panelsRaw), &panels)
				storyboards = append(storyboards, gin.H{"id": bid, "status": bstatus, "summary": summary, "image_url": imageURL, "panel_count": panelCount, "panels": panels, "failure_reason": failure, "created_at": at})
			}
		}
	}
	var background any
	_ = json.Unmarshal([]byte(snapshot), &background)
	var environment string
	_ = db.Get().QueryRow(`SELECT environment FROM users WHERE id=$1`, userID).Scan(&environment)
	config, _ := loadStoryConfig(c.Request.Context(), environment)
	subscribed, _ := userHasActiveSubscription(userID)
	c.JSON(http.StatusOK, gin.H{"id": id, "title": title, "status": status, "current_chapter_no": chapterNo, "companion": gin.H{"id": companionID, "name": companionName}, "background": background, "chapters": chapters, "storyboards": storyboards, "storyboard_unlocked": chapterNo >= config.StoryboardUnlockChapters, "can_continue": subscribed || chapterNo < config.FreeChapterLimit, "config": config, "created_at": created, "updated_at": updated})
}

type advanceStoryInput struct {
	ChoiceID       string `json:"choice_id"`
	IdempotencyKey string `json:"idempotency_key"`
}

func AdvanceStory(c *gin.Context) {
	if companionAgent == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "story generation is unavailable"})
		return
	}
	var input advanceStoryInput
	if err := c.ShouldBindJSON(&input); err != nil || strings.TrimSpace(input.ChoiceID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "choice and idempotency key are required"})
		return
	}
	userID, storyID := c.GetString("user_id"), c.Param("id")
	var companionID, environment, snapshot, choicesRaw string
	var chapterNo int
	err := db.Get().QueryRow(`SELECT s.companion_id,u.environment,s.background_snapshot::text,s.current_chapter_no,ch.choices::text FROM stories s JOIN users u ON u.id=s.user_id JOIN story_chapters ch ON ch.story_id=s.id AND ch.chapter_no=s.current_chapter_no WHERE s.id=$1 AND s.user_id=$2 AND s.status='active'`, storyID, userID).Scan(&companionID, &environment, &snapshot, &chapterNo, &choicesRaw)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "story not found"})
		return
	}
	config, _ := loadStoryConfig(c.Request.Context(), environment)
	subscribed, _ := userHasActiveSubscription(userID)
	if !subscribed && chapterNo >= config.FreeChapterLimit {
		subscriptionRequired(c, "story_chapter_limit_reached", "Subscribe to continue this story")
		return
	}
	var choices []agent.StoryChoice
	_ = json.Unmarshal([]byte(choicesRaw), &choices)
	choiceText := ""
	for _, choice := range choices {
		if choice.ID == input.ChoiceID {
			choiceText = choice.Text
		}
	}
	if choiceText == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid story choice"})
		return
	}
	reservation, err := credits.Reserve(c.Request.Context(), db.Get(), credits.ReserveParams{UserID: userID, CompanionID: companionID, Environment: environment, Platform: c.GetHeader("X-Vita-Platform"), ProductKey: "story_chapter", IdempotencyKey: input.IdempotencyKey, ReferenceType: "story_chapter", Metadata: map[string]any{"story_id": storyID, "chapter_no": chapterNo + 1}})
	if err != nil {
		writeSpendError(c, err)
		return
	}
	if reservation.Idempotent {
		writeStoryDetail(c, storyID, userID)
		return
	}
	var history strings.Builder
	rows, _ := db.Get().Query(`SELECT chapter_no,title,content,selected_choice_text FROM story_chapters WHERE story_id=$1 ORDER BY chapter_no`, storyID)
	if rows != nil {
		for rows.Next() {
			var no int
			var title, content, selected string
			if rows.Scan(&no, &title, &content, &selected) == nil {
				fmt.Fprintf(&history, "章节%d %s\n%s\n选择：%s\n", no, title, content, selected)
			}
		}
		rows.Close()
	}
	chapter, err := companionAgent.GenerateStoryChapter(c.Request.Context(), userID, companionID, snapshot, history.String(), choiceText)
	if err != nil {
		refundStorySpend(reservation.ID, err)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "failed to generate story chapter", "refunded": true})
		return
	}
	chapterID := uuid.New().String()
	encodedChoices, _ := json.Marshal(chapter.Choices)
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err == nil {
		result, updateErr := tx.Exec(`UPDATE story_chapters SET selected_choice_id=$3,selected_choice_text=$4 WHERE story_id=$1 AND chapter_no=$2 AND selected_choice_id=''`, storyID, chapterNo, input.ChoiceID, choiceText)
		err = updateErr
		if err == nil {
			count, _ := result.RowsAffected()
			if count != 1 {
				err = fmt.Errorf("story already advanced")
			}
		}
	}
	if err == nil {
		_, err = tx.Exec(`INSERT INTO story_chapters(id,story_id,chapter_no,title,content,choices) VALUES($1,$2,$3,$4,$5,$6)`, chapterID, storyID, chapterNo+1, chapter.Title, chapter.Content, encodedChoices)
	}
	if err == nil {
		_, err = tx.Exec(`UPDATE stories SET current_chapter_no=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, storyID, chapterNo+1)
	}
	if err == nil {
		err = tx.Commit()
	} else if tx != nil {
		_ = tx.Rollback()
	}
	if err != nil {
		refundStorySpend(reservation.ID, err)
		c.JSON(http.StatusConflict, gin.H{"error": err.Error(), "refunded": true})
		return
	}
	_ = credits.Complete(context.Background(), db.Get(), reservation.ID, chapterID, map[string]any{"story_id": storyID, "chapter_no": chapterNo + 1})
	writeStoryDetail(c, storyID, userID)
}

type storyboardInput struct {
	IdempotencyKey string `json:"idempotency_key"`
	PanelCount     int    `json:"panel_count"`
}

func validStoryboardPanelCount(value int) bool {
	return value == 4 || value == 6 || value == 8 || value == 9
}

func GenerateStoryBoard(c *gin.Context) {
	if companionAgent == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "storyboard generation is unavailable"})
		return
	}
	var input storyboardInput
	if err := c.ShouldBindJSON(&input); err != nil || strings.TrimSpace(input.IdempotencyKey) == "" || !validStoryboardPanelCount(input.PanelCount) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "idempotency key and a panel count of 4, 6, 8, or 9 are required"})
		return
	}
	userID, storyID := c.GetString("user_id"), c.Param("id")
	var companionID, environment string
	var chapterNo int
	if err := db.Get().QueryRow(`SELECT s.companion_id,u.environment,s.current_chapter_no FROM stories s JOIN users u ON u.id=s.user_id WHERE s.id=$1 AND s.user_id=$2`, storyID, userID).Scan(&companionID, &environment, &chapterNo); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "story not found"})
		return
	}
	config, _ := loadStoryConfig(c.Request.Context(), environment)
	if chapterNo < config.StoryboardUnlockChapters {
		c.JSON(http.StatusConflict, gin.H{"error": "storyboard is not unlocked", "code": "storyboard_locked", "required_chapters": config.StoryboardUnlockChapters})
		return
	}
	reservation, err := credits.Reserve(c.Request.Context(), db.Get(), credits.ReserveParams{UserID: userID, CompanionID: companionID, Environment: environment, Platform: c.GetHeader("X-Vita-Platform"), ProductKey: "story_storyboard", IdempotencyKey: input.IdempotencyKey, ReferenceType: "storyboard", Metadata: map[string]any{"story_id": storyID}})
	if err != nil {
		writeSpendError(c, err)
		return
	}
	if reservation.Idempotent {
		writeStoryDetail(c, storyID, userID)
		return
	}
	id := uuid.New().String()
	_, err = db.Get().Exec(`INSERT INTO storyboards(id,story_id,status,panel_count,spend_id) VALUES($1,$2,'pending',$3,$4)`, id, storyID, input.PanelCount, reservation.ID)
	if err != nil {
		refundStorySpend(reservation.ID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to queue storyboard", "refunded": true})
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()
		_ = companionAgent.ProcessPendingStoryboard(ctx)
	}()
	writeStoryDetail(c, storyID, userID)
}

func refundStorySpend(spendID string, cause error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = credits.Refund(ctx, db.Get(), spendID, cause.Error())
}

func AdminGetStoryConfig(c *gin.Context) {
	environment := strings.TrimSpace(c.DefaultQuery("environment", currentEnvironment()))
	config, err := loadStoryConfig(c.Request.Context(), environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load story settings"})
		return
	}
	c.JSON(http.StatusOK, config)
}

func AdminUpdateStoryConfig(c *gin.Context) {
	var input storyConfig
	if err := c.ShouldBindJSON(&input); err != nil || (input.Environment != "dev" && input.Environment != "beta" && input.Environment != "prod") || input.FreeChapterLimit < 0 || input.CustomBackgroundLimit < 0 || input.StoryboardUnlockChapters < 1 || input.ChapterCoins < 1 || input.StoryboardCoins < 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid story settings"})
		return
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err == nil {
		_, err = tx.Exec(`INSERT INTO story_settings(environment,free_chapter_limit,custom_background_limit,storyboard_unlock_chapters) VALUES($1,$2,$3,$4) ON CONFLICT(environment) DO UPDATE SET free_chapter_limit=EXCLUDED.free_chapter_limit,custom_background_limit=EXCLUDED.custom_background_limit,storyboard_unlock_chapters=EXCLUDED.storyboard_unlock_chapters,updated_at=CURRENT_TIMESTAMP`, input.Environment, input.FreeChapterLimit, input.CustomBackgroundLimit, input.StoryboardUnlockChapters)
	}
	if err == nil {
		_, err = tx.Exec(`UPDATE credit_products SET coins=$3,updated_at=CURRENT_TIMESTAMP WHERE environment=$1 AND product_key=$2`, input.Environment, "story_chapter", input.ChapterCoins)
	}
	if err == nil {
		_, err = tx.Exec(`UPDATE credit_products SET coins=$3,updated_at=CURRENT_TIMESTAMP WHERE environment=$1 AND product_key=$2`, input.Environment, "story_storyboard", input.StoryboardCoins)
	}
	if err == nil {
		err = tx.Commit()
	} else if tx != nil {
		_ = tx.Rollback()
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save story settings"})
		return
	}
	c.JSON(http.StatusOK, input)
}

func AdminListStoryBackgrounds(c *gin.Context) {
	environment := strings.TrimSpace(c.DefaultQuery("environment", currentEnvironment()))
	rows, err := db.Get().Query(`SELECT `+storyBackgroundColumns+` FROM story_backgrounds WHERE environment=$1 AND owner_user_id IS NULL AND deleted_at IS NULL ORDER BY sort_order,title`, environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load story backgrounds"})
		return
	}
	defer rows.Close()
	items := []storyBackground{}
	for rows.Next() {
		item, e := scanStoryBackground(rows)
		if e != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read story backgrounds"})
			return
		}
		items = append(items, item)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminCreateStoryBackground(c *gin.Context) {
	saveAdminStoryBackground(c, uuid.New().String(), true)
}
func AdminUpdateStoryBackground(c *gin.Context) { saveAdminStoryBackground(c, c.Param("id"), false) }
func saveAdminStoryBackground(c *gin.Context, id string, create bool) {
	var input storyBackgroundInput
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid story background"})
		return
	}
	normalizeStoryBackgroundInput(&input)
	if err := validateStoryBackgroundInput(input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var err error
	if create {
		_, err = db.Get().Exec(`INSERT INTO story_backgrounds(id,environment,title,cover_url,synopsis,world_setting,opening,genre,character_constraints,story_goal,sort_order,enabled) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`, id, input.Environment, input.Title, input.CoverURL, input.Synopsis, input.WorldSetting, input.Opening, input.Genre, input.CharacterConstraints, input.StoryGoal, input.SortOrder, input.Enabled)
	} else {
		var result sql.Result
		result, err = db.Get().Exec(`UPDATE story_backgrounds SET title=$2,cover_url=$3,synopsis=$4,world_setting=$5,opening=$6,genre=$7,character_constraints=$8,story_goal=$9,sort_order=$10,enabled=$11,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND owner_user_id IS NULL AND environment=$12`, id, input.Title, input.CoverURL, input.Synopsis, input.WorldSetting, input.Opening, input.Genre, input.CharacterConstraints, input.StoryGoal, input.SortOrder, input.Enabled, input.Environment)
		if err == nil {
			n, _ := result.RowsAffected()
			if n == 0 {
				c.JSON(http.StatusNotFound, gin.H{"error": "story background not found"})
				return
			}
		}
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save story background"})
		return
	}
	c.JSON(map[bool]int{true: http.StatusCreated, false: http.StatusOK}[create], gin.H{"id": id})
}

func AdminDeleteStoryBackground(c *gin.Context) {
	result, err := db.Get().Exec(`UPDATE story_backgrounds SET deleted_at=CURRENT_TIMESTAMP,enabled=false,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND owner_user_id IS NULL AND deleted_at IS NULL`, c.Param("id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete story background"})
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "story background not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

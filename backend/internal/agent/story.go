package agent

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"vita/internal/credits"
)

type StoryChoice struct {
	ID   string `json:"id"`
	Text string `json:"text"`
}

type StoryChapter struct {
	Title   string        `json:"title"`
	Content string        `json:"content"`
	Choices []StoryChoice `json:"choices"`
}

type StoryPanel struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Dialogue    string `json:"dialogue"`
	ImagePrompt string `json:"image_prompt"`
	ImageURL    string `json:"image_url"`
}

type Storyboard struct {
	Summary string       `json:"summary"`
	Panels  []StoryPanel `json:"panels"`
}

func cleanJSON(raw string) string {
	clean := strings.TrimSpace(raw)
	clean = strings.TrimPrefix(clean, "```json")
	clean = strings.TrimPrefix(clean, "```")
	clean = strings.TrimSuffix(clean, "```")
	return strings.TrimSpace(clean)
}

// GenerateStoryChapter continues a persisted branching story and always
// returns exactly three irreversible choices for the next chapter.
func (s *Service) GenerateStoryChapter(ctx context.Context, userID, companionID, background, history, selectedChoice string) (StoryChapter, error) {
	var companionName, persona, appearance, backstory string
	if err := s.db.QueryRowContext(ctx, `SELECT name,persona,appearance,backstory FROM companions WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL`, companionID, userID).Scan(&companionName, &persona, &appearance, &backstory); err != nil {
		return StoryChapter{}, err
	}
	if s.mock {
		n := 1 + strings.Count(history, "章节")
		return StoryChapter{Title: fmt.Sprintf("第%d章", n), Content: companionName + "沿着你选择的方向继续前进。新的线索出现了，故事也因此走向未知。", Choices: []StoryChoice{{ID: "a", Text: "追查新线索"}, {ID: "b", Text: "先观察周围"}, {ID: "c", Text: "与 TA 坦诚交谈"}}}, nil
	}
	models, err := s.loadTextRouteModels(ctx, "text_story_chapter", companionID, userID)
	if err != nil {
		return StoryChapter{}, err
	}
	system := `你是互动故事编剧。根据故事背景、角色设定、不可回退的历史章节和用户刚刚选择的发展方向，续写一个连贯章节。避免替用户做选择。严格输出 JSON：{"title":"章节标题","content":"800字以内正文","choices":[{"id":"a","text":"选项"},{"id":"b","text":"选项"},{"id":"c","text":"选项"}]}。choices 必须恰好三个，且能产生明显不同但符合设定的发展。`
	input := fmt.Sprintf("故事背景：%s\n主角：%s\n性格：%s\n外貌：%s\n人物经历：%s\n已发生历史：%s\n本次选择：%s", background, companionName, persona, appearance, backstory, history, selectedChoice)
	raw, _, err := s.generateTextWithFallback(ctx, companionID, "story_chapter", models, GenerateRequest{System: system, Messages: []ChatMessage{{Role: "user", Content: input}}, Temperature: .85, MaxTokens: 1400})
	if err != nil {
		return StoryChapter{}, err
	}
	var result StoryChapter
	if err := json.Unmarshal([]byte(cleanJSON(raw)), &result); err != nil {
		return StoryChapter{}, fmt.Errorf("decode story chapter: %w", err)
	}
	if strings.TrimSpace(result.Title) == "" || strings.TrimSpace(result.Content) == "" || len(result.Choices) != 3 {
		return StoryChapter{}, fmt.Errorf("story chapter response is incomplete")
	}
	for i := range result.Choices {
		if strings.TrimSpace(result.Choices[i].ID) == "" {
			result.Choices[i].ID = string(rune('a' + i))
		}
		if strings.TrimSpace(result.Choices[i].Text) == "" {
			return StoryChapter{}, fmt.Errorf("story chapter choice is empty")
		}
	}
	return result, nil
}

func (s *Service) GenerateStoryboard(ctx context.Context, userID, companionID, story string, panelCount int) (Storyboard, error) {
	if panelCount < 1 || panelCount > 12 {
		panelCount = 8
	}
	if s.mock {
		panels := make([]StoryPanel, panelCount)
		for i := range panels {
			panels[i] = StoryPanel{Title: fmt.Sprintf("镜头 %d", i+1), Description: "故事中的关键一幕", Dialogue: "我们继续走吧。", ImagePrompt: "cinematic interactive story scene"}
		}
		return Storyboard{Summary: "这是你和 TA 共同经历的故事。", Panels: panels}, nil
	}
	models, err := s.loadTextRouteModels(ctx, "text_storyboard", companionID, userID)
	if err != nil {
		return Storyboard{}, err
	}
	system := fmt.Sprintf(`你是分镜师。把完整互动故事提炼成摘要和恰好 %d 个关键镜头。严格输出 JSON：{"summary":"摘要","panels":[{"title":"标题","description":"画面描述","dialogue":"对白或旁白","image_prompt":"英文绘图提示词"}]}。每个提示词都要保持同一主角外貌和统一视觉风格。`, panelCount)
	raw, _, err := s.generateTextWithFallback(ctx, companionID, "storyboard_text", models, GenerateRequest{System: system, Messages: []ChatMessage{{Role: "user", Content: story}}, Temperature: .7, MaxTokens: 2500})
	if err != nil {
		return Storyboard{}, err
	}
	var result Storyboard
	if err := json.Unmarshal([]byte(cleanJSON(raw)), &result); err != nil || len(result.Panels) != panelCount {
		return Storyboard{}, fmt.Errorf("decode storyboard response: %w", err)
	}
	imageModels, err := s.loadModelRouteModels(ctx, "image_storyboard_frame", userID)
	if err != nil {
		return Storyboard{}, err
	}
	var wg sync.WaitGroup
	var firstErr error
	var errMu sync.Mutex
	for i := range result.Panels {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			url, _, imageErr := s.generateImageWithFallback(ctx, companionID, "storyboard_frame", imageModels, GenerateImageRequest{Prompt: result.Panels[index].ImagePrompt, Size: "1024x1024"})
			if imageErr != nil {
				errMu.Lock()
				if firstErr == nil {
					firstErr = imageErr
				}
				errMu.Unlock()
				return
			}
			result.Panels[index].ImageURL = url
		}(i)
	}
	wg.Wait()
	if firstErr != nil {
		return Storyboard{}, firstErr
	}
	return result, nil
}

// ProcessPendingStoryboard claims one durable task. Calling it concurrently is
// safe because only a pending row can transition to generating.
func (s *Service) ProcessPendingStoryboard(ctx context.Context) error {
	// A process can stop after claiming a task. The normal worker timeout is
	// three minutes, so five-minute-old claims are safe to make runnable again.
	if _, err := s.db.ExecContext(ctx, `UPDATE storyboards SET status='pending',updated_at=CURRENT_TIMESTAMP WHERE status='generating' AND updated_at<CURRENT_TIMESTAMP-INTERVAL '5 minutes'`); err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var boardID, storyID, spendID, userID, companionID string
	var panelCount int
	err = tx.QueryRowContext(ctx, `SELECT b.id,b.story_id,COALESCE(b.spend_id,''),s.user_id,s.companion_id,settings.storyboard_panel_count
		FROM storyboards b JOIN stories s ON s.id=b.story_id JOIN users u ON u.id=s.user_id
		JOIN story_settings settings ON settings.environment=u.environment
		WHERE b.status='pending' ORDER BY b.created_at FOR UPDATE OF b SKIP LOCKED LIMIT 1`).Scan(&boardID, &storyID, &spendID, &userID, &companionID, &panelCount)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `UPDATE storyboards SET status='generating',updated_at=CURRENT_TIMESTAMP WHERE id=$1`, boardID); err != nil {
		return err
	}
	if err = tx.Commit(); err != nil {
		return err
	}

	var story strings.Builder
	rows, err := s.db.QueryContext(ctx, `SELECT title,content,selected_choice_text FROM story_chapters WHERE story_id=$1 ORDER BY chapter_no`, storyID)
	if err == nil {
		for rows.Next() {
			var title, content, choice string
			if scanErr := rows.Scan(&title, &content, &choice); scanErr != nil {
				err = scanErr
				break
			}
			fmt.Fprintf(&story, "%s\n%s\n选择：%s\n", title, content, choice)
		}
		rows.Close()
	}
	if err == nil {
		var board Storyboard
		board, err = s.GenerateStoryboard(ctx, userID, companionID, story.String(), panelCount)
		if err == nil {
			panels, _ := json.Marshal(board.Panels)
			_, err = s.db.ExecContext(ctx, `UPDATE storyboards SET status='completed',summary=$2,panels=$3,failure_reason='',updated_at=CURRENT_TIMESTAMP WHERE id=$1`, boardID, board.Summary, panels)
		}
	}
	settlementCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err != nil {
		_, _ = s.db.ExecContext(settlementCtx, `UPDATE storyboards SET status='failed',failure_reason=$2,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, boardID, err.Error())
		if spendID != "" {
			_ = credits.Refund(settlementCtx, s.db, spendID, err.Error())
		}
		return err
	}
	if spendID != "" {
		if err := credits.Complete(settlementCtx, s.db, spendID, boardID, map[string]any{"story_id": storyID}); err != nil {
			return err
		}
	}
	return nil
}

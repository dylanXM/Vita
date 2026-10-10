package handler

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

type localizedCopy map[string]string

type onboardingPage struct {
	ID       string        `json:"id"`
	ImageURL string        `json:"image_url"`
	Icon     string        `json:"icon"`
	Title    localizedCopy `json:"title"`
	Body     localizedCopy `json:"body"`
}

type onboardingConfig struct {
	Environment string           `json:"environment"`
	Platform    string           `json:"platform"`
	Enabled     bool             `json:"enabled"`
	Revision    int              `json:"revision"`
	Pages       []onboardingPage `json:"pages"`
	UpdatedBy   string           `json:"updated_by"`
	UpdatedAt   time.Time        `json:"updated_at"`
}

type whatsNewPage struct {
	ID        string        `json:"id"`
	ImageURL  string        `json:"image_url"`
	Icon      string        `json:"icon"`
	Title     localizedCopy `json:"title"`
	Body      localizedCopy `json:"body"`
	CTALabel  localizedCopy `json:"cta_label"`
	CTAAction string        `json:"cta_action"`
	CTAValue  string        `json:"cta_value"`
}

type whatsNewCampaign struct {
	ID            string         `json:"id"`
	Name          string         `json:"name"`
	Environment   string         `json:"environment"`
	Platform      string         `json:"platform"`
	MinAppVersion string         `json:"min_app_version"`
	Enabled       bool           `json:"enabled"`
	StartsAt      *time.Time     `json:"starts_at"`
	EndsAt        *time.Time     `json:"ends_at"`
	Pages         []whatsNewPage `json:"pages"`
	UpdatedBy     string         `json:"updated_by"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
}

type socialMediaLinks struct {
	Environment  string    `json:"environment"`
	InstagramURL string    `json:"social_instagram_url"`
	TiktokURL    string    `json:"social_tiktok_url"`
	XURL         string    `json:"social_x_url"`
	DiscordURL   string    `json:"social_discord_url"`
	UpdatedBy    string    `json:"updated_by"`
	UpdatedAt    time.Time `json:"updated_at"`
}

func defaultOnboardingPages() []onboardingPage {
	return []onboardingPage{
		{ID: "meet", Icon: "chat", Title: localizedCopy{
			"en": "Meet an AI companion with a life of their own", "zh": "遇见有自己日常的 AI 伴侣", "zh_TW": "遇見有自己日常的 AI 伴侶",
			"es": "Conoce a un compañero de IA con vida propia", "pt": "Conheça um companheiro de IA com vida própria",
			"ja": "自分の日常を持つAIコンパニオンと出会う", "ko": "자신만의 일상을 가진 AI 동반자를 만나보세요",
			"ar": "تعرّف على رفيق ذكاء اصطناعي له حياته الخاصة",
		}, Body: localizedCopy{"en": "Talk naturally, build memories, and let your relationship grow over time.", "zh": "自然地聊天、共同积累回忆，让关系随着时间慢慢生长。"}},
		{ID: "life", Icon: "life", Title: localizedCopy{
			"en": "More than a chat", "zh": "不止于聊天", "zh_TW": "不止於聊天",
			"es": "Más que una conversación", "pt": "Mais que uma conversa",
			"ja": "会話だけではない体験", "ko": "대화 그 이상의 경험", "ar": "أكثر من مجرد محادثة",
		}, Body: localizedCopy{
			"en":    "Begin with a conversation and a visit. The full experience adds a daily rhythm, life events, and messages your companion initiates.",
			"zh":    "从一次对话和拜访开始；解锁完整体验后，TA 会拥有日常节奏、生活事件，也会主动联系你。",
			"zh_TW": "從一次對話和拜訪開始；解鎖完整體驗後，TA 會擁有日常節奏、生活事件，也會主動聯繫你。",
			"es":    "Empieza con una charla y una visita. La experiencia completa añade una rutina, eventos y mensajes iniciados por tu compañero.",
			"pt":    "Comece com uma conversa e uma visita. A experiência completa inclui uma rotina, acontecimentos e mensagens iniciadas pelo seu companheiro.",
			"ja":    "会話と訪問から始めましょう。フル体験では、日々の暮らしや出来事、コンパニオンからの連絡が加わります。",
			"ko":    "대화와 방문으로 시작하세요. 전체 경험에서는 동반자의 일상과 사건, 먼저 보내는 메시지가 더해집니다.",
			"ar":    "ابدأ بمحادثة وزيارة. تضيف التجربة الكاملة حياة يومية وأحداثًا ورسائل يبدأها رفيقك.",
		}},
		{ID: "distance", Icon: "infinity", Title: localizedCopy{
			"en": "Moments worth remembering", "zh": "值得记住的相处", "zh_TW": "值得記住的相處",
			"es": "Momentos que vale la pena recordar", "pt": "Momentos que valem a pena lembrar",
			"ja": "記憶に残したい時間", "ko": "기억하고 싶은 순간", "ar": "لحظات تستحق التذكر",
		}, Body: localizedCopy{
			"en":    "Share conversations and memories with an AI companion who remembers your time together.",
			"zh":    "与 AI 伴侣分享对话和回忆，让你们共度的时光被认真记住。",
			"zh_TW": "與 AI 伴侶分享對話和回憶，讓你們共度的時光被認真記住。",
			"es":    "Comparte conversaciones y recuerdos con un compañero de IA que recuerda el tiempo que pasan juntos.",
			"pt":    "Compartilhe conversas e memórias com um companheiro de IA que se lembra do tempo que passam juntos.",
			"ja":    "AIコンパニオンと会話や思い出を重ね、一緒に過ごした時間を大切に残しましょう。",
			"ko":    "AI 동반자와 대화와 추억을 나누고 함께한 시간을 기억하게 하세요.",
			"ar":    "شارك الأحاديث والذكريات مع رفيق ذكاء اصطناعي يتذكر الوقت الذي قضيتماه معًا.",
		}},
	}
}

func normalizeMobilePlatform(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "android":
		return "android"
	default:
		return "ios"
	}
}

func validMobilePlatform(value string) bool { return value == "ios" || value == "android" }

func adminContentScope(c *gin.Context) (string, string, bool) {
	environment := currentEnvironment()
	platform := strings.ToLower(strings.TrimSpace(c.Query("platform")))
	if !validMobilePlatform(platform) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "platform is required"})
		return "", "", false
	}
	return environment, platform, true
}

func contentOperator(c *gin.Context) string {
	var email string
	if id := c.GetString("user_id"); id != "" {
		_ = db.Get().QueryRow(`SELECT email FROM users WHERE id=$1`, id).Scan(&email)
	}
	return email
}

func readOnboarding(environment, platform string) (onboardingConfig, error) {
	var output onboardingConfig
	var raw []byte
	err := db.Get().QueryRow(`SELECT environment,platform,enabled,revision,pages,updated_by,updated_at
		FROM onboarding_configs WHERE environment=$1 AND platform=$2`, environment, platform).Scan(
		&output.Environment, &output.Platform, &output.Enabled, &output.Revision, &raw, &output.UpdatedBy, &output.UpdatedAt)
	if err != nil {
		return output, err
	}
	if err := json.Unmarshal(raw, &output.Pages); err != nil {
		return output, err
	}
	if len(output.Pages) == 0 {
		output.Pages = defaultOnboardingPages()
	}
	// Replace only the former bundled claims. Admin-authored copy stays intact.
	defaults := defaultOnboardingPages()
	for i := range output.Pages {
		switch output.Pages[i].ID {
		case "meet":
			if output.Pages[i].Title["en"] == "A person who feels present" && output.Pages[i].Title["zh"] == "遇见一个真实存在的人" {
				output.Pages[i].Title = defaults[0].Title
			}
		case "life":
			if output.Pages[i].Title["en"] == "Their life continues" && output.Pages[i].Title["zh"] == "TA 的生活一直在继续" {
				output.Pages[i].Title = defaults[1].Title
			}
			if output.Pages[i].Body["en"] == "Your companion has a daily rhythm, experiences events, and may reach out first." && output.Pages[i].Body["zh"] == "你的伴侣拥有自己的日常节奏，会经历生活事件，也会主动联系你。" {
				output.Pages[i].Body = defaults[1].Body
			}
		case "distance":
			if output.Pages[i].Title["en"] == "Close, even from afar" && output.Pages[i].Title["zh"] == "相隔远方，依然靠近" {
				output.Pages[i].Title = defaults[2].Title
			}
			if output.Pages[i].Body["en"] == "The only distance between you is that you cannot meet in the real world." && output.Pages[i].Body["zh"] == "你们唯一的距离，是暂时无法在现实世界见面。" {
				output.Pages[i].Body = defaults[2].Body
			}
		}
	}
	return output, nil
}

func readSocialMediaLinks(environment string) (socialMediaLinks, error) {
	var output socialMediaLinks
	err := db.Get().QueryRow(`SELECT environment,instagram_url,tiktok_url,x_url,discord_url,updated_by,updated_at
		FROM social_media_links WHERE environment=$1`, environment).Scan(
		&output.Environment, &output.InstagramURL, &output.TiktokURL, &output.XURL,
		&output.DiscordURL, &output.UpdatedBy, &output.UpdatedAt)
	return output, err
}

// AppContent is public because onboarding must load before authentication.
func AppContent(c *gin.Context) {
	environment := currentEnvironment()
	platform := normalizeMobilePlatform(c.GetHeader("X-Vita-Platform"))
	onboarding, err := readOnboarding(environment, platform)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load app content"})
		return
	}
	socialLinks, err := readSocialMediaLinks(environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load app content"})
		return
	}
	legalDocuments, err := activeLegalDocuments(environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load app content"})
		return
	}

	var campaign *whatsNewCampaign
	rows, err := db.Get().Query(`SELECT id,name,environment,platform,min_app_version,enabled,starts_at,ends_at,pages,updated_by,created_at,updated_at
		FROM whats_new_campaigns WHERE environment=$1 AND platform=$2 AND enabled=true
		AND (starts_at IS NULL OR starts_at<=CURRENT_TIMESTAMP)
		AND (ends_at IS NULL OR ends_at>CURRENT_TIMESTAMP)
		ORDER BY starts_at DESC NULLS LAST,updated_at DESC`, environment, platform)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			item, scanErr := scanWhatsNew(rows)
			if scanErr == nil && versionAtLeast(c.GetHeader("X-Vita-App-Version"), item.MinAppVersion) {
				campaign = &item
				break
			}
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"onboarding":      onboarding,
		"whats_new":       campaign,
		"social_links":    socialLinks,
		"legal_documents": legalDocumentsForApp(legalDocuments),
	})
}

func AdminGetSocialMediaLinks(c *gin.Context) {
	environment := currentEnvironment()
	output, err := readSocialMediaLinks(environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load social media links"})
		return
	}
	c.JSON(http.StatusOK, output)
}

func AdminUpdateSocialMediaLinks(c *gin.Context) {
	environment := currentEnvironment()
	var input socialMediaLinks
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid social media links"})
		return
	}
	values := []*string{&input.InstagramURL, &input.TiktokURL, &input.XURL, &input.DiscordURL}
	for _, value := range values {
		normalized, ok := normalizeExternalURL(*value)
		if !ok {
			c.JSON(http.StatusBadRequest, gin.H{"error": "social media links must use http or https"})
			return
		}
		*value = normalized
	}
	_, err := db.Get().Exec(`INSERT INTO social_media_links(
		environment,instagram_url,tiktok_url,x_url,discord_url,updated_by,updated_at)
		VALUES($1,$2,$3,$4,$5,$6,CURRENT_TIMESTAMP)
		ON CONFLICT(environment) DO UPDATE SET instagram_url=EXCLUDED.instagram_url,
		tiktok_url=EXCLUDED.tiktok_url,x_url=EXCLUDED.x_url,discord_url=EXCLUDED.discord_url,
		updated_by=EXCLUDED.updated_by,updated_at=CURRENT_TIMESTAMP`, environment,
		input.InstagramURL, input.TiktokURL, input.XURL, input.DiscordURL, contentOperator(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save social media links"})
		return
	}
	output, err := readSocialMediaLinks(environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reload social media links"})
		return
	}
	c.JSON(http.StatusOK, output)
}

func normalizeExternalURL(value string) (string, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", true
	}
	parsed, err := url.ParseRequestURI(value)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return "", false
	}
	return value, true
}

func AdminGetOnboarding(c *gin.Context) {
	environment, platform, ok := adminContentScope(c)
	if !ok {
		return
	}
	output, err := readOnboarding(environment, platform)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load onboarding"})
		return
	}
	c.JSON(http.StatusOK, output)
}

func AdminUpdateOnboarding(c *gin.Context) {
	environment, platform, ok := adminContentScope(c)
	if !ok {
		return
	}
	var input struct {
		Enabled  bool             `json:"enabled"`
		Revision int              `json:"revision"`
		Pages    []onboardingPage `json:"pages"`
	}
	if err := c.ShouldBindJSON(&input); err != nil || input.Revision < 1 || len(input.Pages) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "revision and at least one page are required"})
		return
	}
	for i := range input.Pages {
		input.Pages[i].ID = strings.TrimSpace(input.Pages[i].ID)
		if input.Pages[i].ID == "" || len(input.Pages[i].Title) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "every page requires id and title"})
			return
		}
	}
	raw, _ := json.Marshal(input.Pages)
	_, err := db.Get().Exec(`UPDATE onboarding_configs SET enabled=$3,revision=$4,pages=$5,updated_by=$6,updated_at=CURRENT_TIMESTAMP
		WHERE environment=$1 AND platform=$2`, environment, platform, input.Enabled, input.Revision, raw, contentOperator(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save onboarding"})
		return
	}
	output, _ := readOnboarding(environment, platform)
	c.JSON(http.StatusOK, output)
}

func AdminListWhatsNew(c *gin.Context) {
	environment, platform, ok := adminContentScope(c)
	if !ok {
		return
	}
	rows, err := db.Get().Query(`SELECT id,name,environment,platform,min_app_version,enabled,starts_at,ends_at,pages,updated_by,created_at,updated_at
		FROM whats_new_campaigns WHERE environment=$1 AND platform=$2 ORDER BY updated_at DESC`, environment, platform)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list campaigns"})
		return
	}
	defer rows.Close()
	items := make([]whatsNewCampaign, 0)
	for rows.Next() {
		item, scanErr := scanWhatsNew(rows)
		if scanErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read campaigns"})
			return
		}
		items = append(items, item)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminCreateWhatsNew(c *gin.Context) { saveWhatsNew(c, "") }
func AdminUpdateWhatsNew(c *gin.Context) { saveWhatsNew(c, c.Param("id")) }

func saveWhatsNew(c *gin.Context, id string) {
	var input whatsNewCampaign
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid campaign"})
		return
	}
	input.Name = strings.TrimSpace(input.Name)
	input.Environment = currentEnvironment()
	input.Platform = strings.ToLower(strings.TrimSpace(input.Platform))
	input.MinAppVersion = strings.TrimSpace(input.MinAppVersion)
	if input.Name == "" || !validMobilePlatform(input.Platform) || len(input.Pages) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name, scope, and at least one page are required"})
		return
	}
	if input.StartsAt != nil && input.EndsAt != nil && !input.EndsAt.After(*input.StartsAt) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "end time must be after start time"})
		return
	}
	for _, page := range input.Pages {
		if strings.TrimSpace(page.ID) == "" || len(page.Title) == 0 || !validCTAAction(page.CTAAction) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "every page requires id, title, and a valid action"})
			return
		}
	}
	raw, _ := json.Marshal(input.Pages)
	operator := contentOperator(c)
	if id == "" {
		id = uuid.NewString()
		_, err := db.Get().Exec(`INSERT INTO whats_new_campaigns(id,name,environment,platform,min_app_version,enabled,starts_at,ends_at,pages,updated_by)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, id, input.Name, input.Environment, input.Platform, input.MinAppVersion, input.Enabled, input.StartsAt, input.EndsAt, raw, operator)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create campaign"})
			return
		}
		c.Status(http.StatusCreated)
	} else {
		result, err := db.Get().Exec(`UPDATE whats_new_campaigns SET name=$2,environment=$3,platform=$4,min_app_version=$5,enabled=$6,starts_at=$7,ends_at=$8,pages=$9,updated_by=$10,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, id, input.Name, input.Environment, input.Platform, input.MinAppVersion, input.Enabled, input.StartsAt, input.EndsAt, raw, operator)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update campaign"})
			return
		}
		if n, _ := result.RowsAffected(); n == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "campaign not found"})
			return
		}
	}
	item, err := getWhatsNew(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reload campaign"})
		return
	}
	c.JSON(http.StatusOK, item)
}

func AdminDeleteWhatsNew(c *gin.Context) {
	result, err := db.Get().Exec(`DELETE FROM whats_new_campaigns WHERE id=$1`, c.Param("id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete campaign"})
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "campaign not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

func scanWhatsNew(row rowScanner) (whatsNewCampaign, error) {
	var item whatsNewCampaign
	var startsAt, endsAt sql.NullTime
	var raw []byte
	err := row.Scan(&item.ID, &item.Name, &item.Environment, &item.Platform, &item.MinAppVersion, &item.Enabled, &startsAt, &endsAt, &raw, &item.UpdatedBy, &item.CreatedAt, &item.UpdatedAt)
	if err != nil {
		return item, err
	}
	if startsAt.Valid {
		item.StartsAt = &startsAt.Time
	}
	if endsAt.Valid {
		item.EndsAt = &endsAt.Time
	}
	err = json.Unmarshal(raw, &item.Pages)
	return item, err
}

func getWhatsNew(id string) (whatsNewCampaign, error) {
	return scanWhatsNew(db.Get().QueryRow(`SELECT id,name,environment,platform,min_app_version,enabled,starts_at,ends_at,pages,updated_by,created_at,updated_at FROM whats_new_campaigns WHERE id=$1`, id))
}

func validCTAAction(value string) bool {
	switch strings.TrimSpace(value) {
	case "", "next", "close", "route", "url":
		return true
	default:
		return false
	}
}

func versionAtLeast(current, minimum string) bool {
	if strings.TrimSpace(minimum) == "" {
		return true
	}
	if strings.TrimSpace(current) == "" {
		return false
	}
	parse := func(value string) [3]int {
		var out [3]int
		for i, part := range strings.Split(strings.SplitN(value, "-", 2)[0], ".") {
			if i >= 3 {
				break
			}
			out[i], _ = strconv.Atoi(part)
		}
		return out
	}
	a, b := parse(current), parse(minimum)
	for i := 0; i < 3; i++ {
		if a[i] != b[i] {
			return a[i] > b[i]
		}
	}
	return true
}

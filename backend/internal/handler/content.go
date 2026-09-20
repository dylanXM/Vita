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

	"vita/internal/config"
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
		{ID: "meet", Icon: "chat", Title: localizedCopy{"en": "A person who feels present", "zh": "遇见一个真实存在的人"}, Body: localizedCopy{"en": "Talk naturally, build memories, and let your relationship grow over time.", "zh": "自然地聊天、共同积累回忆，让关系随着时间慢慢生长。"}},
		{ID: "life", Icon: "life", Title: localizedCopy{"en": "Their life continues", "zh": "TA 的生活一直在继续"}, Body: localizedCopy{"en": "Your companion has a daily rhythm, experiences events, and may reach out first.", "zh": "你的伴侣拥有自己的日常节奏，会经历生活事件，也会主动联系你。"}},
		{ID: "distance", Icon: "infinity", Title: localizedCopy{"en": "Close, even from afar", "zh": "相隔远方，依然靠近"}, Body: localizedCopy{"en": "The only distance between you is that you cannot meet in the real world.", "zh": "你们唯一的距离，是暂时无法在现实世界见面。"}},
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
	environment := strings.TrimSpace(c.Query("environment"))
	platform := strings.ToLower(strings.TrimSpace(c.Query("platform")))
	if !config.IsValidEnvironment(environment) || !validMobilePlatform(platform) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "environment and platform are required"})
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
	environment := strings.TrimSpace(c.Query("environment"))
	if !config.IsValidEnvironment(environment) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "environment is required"})
		return
	}
	output, err := readSocialMediaLinks(environment)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load social media links"})
		return
	}
	c.JSON(http.StatusOK, output)
}

func AdminUpdateSocialMediaLinks(c *gin.Context) {
	environment := strings.TrimSpace(c.Query("environment"))
	if !config.IsValidEnvironment(environment) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "environment is required"})
		return
	}
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
	input.Environment = strings.TrimSpace(input.Environment)
	input.Platform = strings.ToLower(strings.TrimSpace(input.Platform))
	input.MinAppVersion = strings.TrimSpace(input.MinAppVersion)
	if input.Name == "" || !config.IsValidEnvironment(input.Environment) || !validMobilePlatform(input.Platform) || len(input.Pages) == 0 {
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

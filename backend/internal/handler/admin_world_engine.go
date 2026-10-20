package handler

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vita/internal/db"
)

type worldPlaceInput struct {
	Title       string `json:"title" binding:"required"`
	Description string `json:"description"`
	Enabled     bool   `json:"enabled"`
}

func validWorldKind(kind string) bool {
	switch kind {
	case "home", "work", "cafe", "outdoors", "story":
		return true
	}
	return false
}

func AdminWorldPlaces(c *gin.Context) {
	rows, err := db.Get().QueryContext(c.Request.Context(), `SELECT scene_kind,title,description,enabled,updated_at FROM world_places WHERE environment=$1 ORDER BY scene_kind`, currentEnvironment())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list world places"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var kind, title, description string
		var enabled bool
		var updated time.Time
		if err := rows.Scan(&kind, &title, &description, &enabled, &updated); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read world place"})
			return
		}
		items = append(items, gin.H{"scene_kind": kind, "title": title, "description": description, "enabled": enabled, "updated_at": updated})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read world places"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminUpdateWorldPlace(c *gin.Context) {
	kind := c.Param("kind")
	if !validWorldKind(kind) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid scene kind"})
		return
	}
	var input worldPlaceInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid world place"})
		return
	}
	input.Title = strings.TrimSpace(input.Title)
	input.Description = strings.TrimSpace(input.Description)
	if input.Title == "" || len([]rune(input.Title)) > 80 || len([]rune(input.Description)) > 300 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "world place title or description is invalid"})
		return
	}
	_, err := db.Get().ExecContext(c.Request.Context(), `INSERT INTO world_places(id,environment,scene_kind,title,description,enabled)
		VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(environment,scene_kind) DO UPDATE
		SET title=EXCLUDED.title,description=EXCLUDED.description,enabled=EXCLUDED.enabled,updated_at=CURRENT_TIMESTAMP`,
		"world-"+currentEnvironment()+"-"+kind, currentEnvironment(), kind, input.Title, input.Description, input.Enabled)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save world place"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "world place saved"})
}

type worldCampaignInput struct {
	RegionCode  string `json:"region_code" binding:"required"`
	Title       string `json:"title" binding:"required"`
	Description string `json:"description"`
	SceneKind   string `json:"scene_kind" binding:"required"`
	Ambience    string `json:"ambience"`
	StartsOn    string `json:"starts_on" binding:"required"`
	EndsOn      string `json:"ends_on" binding:"required"`
	Priority    int    `json:"priority"`
	Enabled     bool   `json:"enabled"`
}

func validateWorldCampaign(input *worldCampaignInput) error {
	input.RegionCode = strings.ToUpper(strings.TrimSpace(input.RegionCode))
	if input.RegionCode == "GLOBAL" {
		input.RegionCode = "global"
	}
	input.Title = strings.TrimSpace(input.Title)
	input.Description = strings.TrimSpace(input.Description)
	if input.Ambience == "" {
		input.Ambience = "clear"
	}
	if input.RegionCode != "global" && !worldRegionPattern.MatchString(input.RegionCode) {
		return errors.New("invalid region code")
	}
	if !validWorldKind(input.SceneKind) || input.Title == "" || len([]rune(input.Title)) > 100 || len([]rune(input.Description)) > 500 {
		return errors.New("invalid campaign content")
	}
	if input.Ambience != "clear" && input.Ambience != "rain" && input.Ambience != "snow" {
		return errors.New("invalid world ambience")
	}
	start, err := time.Parse("2006-01-02", input.StartsOn)
	if err != nil {
		return errors.New("invalid start date")
	}
	end, err := time.Parse("2006-01-02", input.EndsOn)
	if err != nil || end.Before(start) {
		return errors.New("invalid end date")
	}
	if end.Sub(start) > 366*24*time.Hour || input.Priority < -1000 || input.Priority > 1000 {
		return errors.New("campaign duration or priority is out of range")
	}
	return nil
}

func AdminWorldCampaigns(c *gin.Context) {
	rows, err := db.Get().QueryContext(c.Request.Context(), `SELECT id,region_code,title,description,scene_kind,ambience,starts_on,ends_on,priority,enabled,updated_at
		FROM world_campaigns WHERE environment=$1 ORDER BY starts_on DESC,priority DESC,id DESC LIMIT 200`, currentEnvironment())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list world campaigns"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, region, title, description, kind, ambience string
		var starts, ends, updated time.Time
		var priority int
		var enabled bool
		if err := rows.Scan(&id, &region, &title, &description, &kind, &ambience, &starts, &ends, &priority, &enabled, &updated); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read world campaign"})
			return
		}
		items = append(items, gin.H{"id": id, "region_code": region, "title": title, "description": description, "scene_kind": kind, "ambience": ambience,
			"starts_on": starts.Format("2006-01-02"), "ends_on": ends.Format("2006-01-02"), "priority": priority, "enabled": enabled, "updated_at": updated})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read world campaigns"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminSaveWorldCampaign(c *gin.Context) {
	var input worldCampaignInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid world campaign"})
		return
	}
	if err := validateWorldCampaign(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	id := c.Param("id")
	if id == "" {
		id = uuid.New().String()
		_, err := db.Get().ExecContext(c.Request.Context(), `INSERT INTO world_campaigns(id,environment,region_code,title,description,scene_kind,ambience,starts_on,ends_on,priority,enabled)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`, id, currentEnvironment(), input.RegionCode, input.Title, input.Description, input.SceneKind,
			input.Ambience, input.StartsOn, input.EndsOn, input.Priority, input.Enabled)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create world campaign"})
			return
		}
		c.JSON(http.StatusCreated, gin.H{"id": id})
		return
	}
	result, err := db.Get().ExecContext(c.Request.Context(), `UPDATE world_campaigns SET region_code=$3,title=$4,description=$5,scene_kind=$6,ambience=$7,
		starts_on=$8,ends_on=$9,priority=$10,enabled=$11,updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND environment=$2`,
		id, currentEnvironment(), input.RegionCode, input.Title, input.Description, input.SceneKind, input.Ambience, input.StartsOn, input.EndsOn, input.Priority, input.Enabled)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update world campaign"})
		return
	}
	count, err := result.RowsAffected()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify world campaign"})
		return
	}
	if count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "world campaign not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": id})
}

func AdminDeleteWorldCampaign(c *gin.Context) {
	result, err := db.Get().ExecContext(c.Request.Context(), `DELETE FROM world_campaigns WHERE id=$1 AND environment=$2`, c.Param("id"), currentEnvironment())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete world campaign"})
		return
	}
	count, err := result.RowsAffected()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to verify world campaign deletion"})
		return
	}
	if count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "world campaign not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "world campaign deleted"})
}

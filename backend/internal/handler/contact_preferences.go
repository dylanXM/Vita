package handler

import (
	"database/sql"
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"vita/internal/agent"
	"vita/internal/db"
)

func contactUserID(c *gin.Context, admin bool) string {
	if admin {
		return c.Param("id")
	}
	return c.GetString("user_id")
}

func getContactPreferences(c *gin.Context, admin bool) {
	id := contactUserID(c, admin)
	var timezone string
	err := db.Get().QueryRowContext(c.Request.Context(), `SELECT COALESCE(timezone,'UTC') FROM users WHERE id=$1`, id).Scan(&timezone)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		return
	}
	p, err := agent.LoadContactPreferences(c.Request.Context(), db.Get(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load contact preferences"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"preferences": p, "timezone": timezone})
}

func saveContactPreferences(c *gin.Context, admin bool) {
	// Require every field: a missing boolean must not silently disable quiet hours.
	var input struct {
		DailyLimit        *int  `json:"daily_limit"`
		MinimumGapMinutes *int  `json:"minimum_gap_minutes"`
		QuietEnabled      *bool `json:"quiet_enabled"`
		QuietStart        *int  `json:"quiet_start"`
		QuietEnd          *int  `json:"quiet_end"`
	}
	if c.ShouldBindJSON(&input) != nil || input.DailyLimit == nil || input.MinimumGapMinutes == nil || input.QuietEnabled == nil || input.QuietStart == nil || input.QuietEnd == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "all contact preference fields are required"})
		return
	}
	p := agent.ContactPreferences{DailyLimit: *input.DailyLimit, MinimumGapMinutes: *input.MinimumGapMinutes, QuietEnabled: *input.QuietEnabled, QuietStart: *input.QuietStart, QuietEnd: *input.QuietEnd}
	if err := p.Validate(); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	id := contactUserID(c, admin)
	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save contact preferences"})
		return
	}
	defer tx.Rollback()
	var locked string
	err = tx.QueryRowContext(c.Request.Context(), `SELECT id FROM users WHERE id=$1 FOR UPDATE`, id).Scan(&locked)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	if err == nil {
		_, err = tx.ExecContext(c.Request.Context(), `INSERT INTO user_contact_preferences(user_id,daily_limit,minimum_gap_minutes,quiet_enabled,quiet_start,quiet_end)
 VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(user_id) DO UPDATE SET daily_limit=$2,minimum_gap_minutes=$3,quiet_enabled=$4,quiet_start=$5,quiet_end=$6`, id, p.DailyLimit, p.MinimumGapMinutes, p.QuietEnabled, p.QuietStart, p.QuietEnd)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save contact preferences"})
		return
	}
	getContactPreferences(c, admin)
}

func GetContactPreferences(c *gin.Context)         { getContactPreferences(c, false) }
func UpdateContactPreferences(c *gin.Context)      { saveContactPreferences(c, false) }
func AdminGetContactPreferences(c *gin.Context)    { getContactPreferences(c, true) }
func AdminUpdateContactPreferences(c *gin.Context) { saveContactPreferences(c, true) }

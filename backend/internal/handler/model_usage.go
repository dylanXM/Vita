package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"vita/internal/agent"
	"vita/internal/db"
)

type modelCostTotals struct {
	Today    float64 `json:"today_usd"`
	Total    float64 `json:"total_usd"`
	Calls    int64   `json:"calls"`
	Unpriced int64   `json:"unpriced_calls"`
}

func collectModelCost(ctx context.Context, id string) (modelCostTotals, error) {
	var totals modelCostTotals
	err := db.Get().QueryRowContext(ctx, `SELECT
 COALESCE(SUM(estimated_cost_usd) FILTER (WHERE started_at >= (date_trunc('day',CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai')),0),
 COALESCE(SUM(estimated_cost_usd),0),COUNT(*),COUNT(*) FILTER (WHERE estimated_cost_usd IS NULL)
 FROM model_calls WHERE ($1='' OR model_id=$1)`, id).Scan(&totals.Today, &totals.Total, &totals.Calls, &totals.Unpriced)
	return totals, err
}
func AdminModelUsage(c *gin.Context) {
	id := c.Param("id")
	var exists bool
	if err := db.Get().QueryRowContext(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM ai_models WHERE id=$1)`, id).Scan(&exists); err != nil {
		c.JSON(500, gin.H{"error": "failed to read model"})
		return
	}
	if !exists {
		c.JSON(404, gin.H{"error": "model not found"})
		return
	}
	rates := agent.ModelRates{Unit: "tokens"}
	err := db.Get().QueryRowContext(c.Request.Context(), `SELECT unit,input_usd,output_usd,cache_read_usd,cache_write_usd,call_usd FROM ai_model_rates WHERE model_id=$1`, id).Scan(&rates.Unit, &rates.Input, &rates.Output, &rates.CacheRead, &rates.CacheWrite, &rates.Call)
	if err != nil && err != sql.ErrNoRows {
		c.JSON(500, gin.H{"error": "failed to read rates"})
		return
	}
	totals, err := collectModelCost(c.Request.Context(), id)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to read cost totals"})
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 || page > 2000 {
		c.JSON(400, gin.H{"error": "invalid page"})
		return
	}
	rows, err := db.Get().QueryContext(c.Request.Context(), `SELECT id,kind,status,request_summary,response_summary,error,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,usage_known,rates::text,estimated_cost_usd,started_at,finished_at FROM model_calls WHERE model_id=$1 ORDER BY started_at DESC,id DESC LIMIT 51 OFFSET $2`, id, (page-1)*50)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to read model history"})
		return
	}
	defer rows.Close()
	type call struct {
		ID         string          `json:"id"`
		Kind       string          `json:"kind"`
		Status     string          `json:"status"`
		Request    string          `json:"request"`
		Response   string          `json:"response"`
		Error      string          `json:"error"`
		Input      int64           `json:"input_tokens"`
		Output     int64           `json:"output_tokens"`
		CacheRead  int64           `json:"cache_read_tokens"`
		CacheWrite int64           `json:"cache_write_tokens"`
		UsageKnown bool            `json:"usage_known"`
		Rates      json.RawMessage `json:"rates"`
		Cost       *float64        `json:"estimated_cost_usd"`
		Started    time.Time       `json:"started_at"`
		Finished   time.Time       `json:"finished_at"`
	}
	items := make([]call, 0)
	for rows.Next() {
		var item call
		var raw string
		if err := rows.Scan(&item.ID, &item.Kind, &item.Status, &item.Request, &item.Response, &item.Error, &item.Input, &item.Output, &item.CacheRead, &item.CacheWrite, &item.UsageKnown, &raw, &item.Cost, &item.Started, &item.Finished); err != nil {
			c.JSON(500, gin.H{"error": "failed to read history"})
			return
		}
		item.Rates = json.RawMessage(raw)
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		c.JSON(500, gin.H{"error": "failed to read history"})
		return
	}
	more := len(items) > 50
	if more {
		items = items[:50]
	}
	// Older agent_runs contain outcomes but not token usage or provider prices.
	oldRows, err := db.Get().QueryContext(c.Request.Context(), `SELECT kind,status,error,COALESCE(input_summary,''),finished_at FROM agent_runs WHERE model_id=$1 AND finished_at < COALESCE((SELECT MIN(started_at) FROM model_calls WHERE model_id=$1),'infinity'::timestamptz) ORDER BY finished_at DESC LIMIT 50`, id)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to read legacy history"})
		return
	}
	defer oldRows.Close()
	old := make([]gin.H, 0)
	for oldRows.Next() {
		var kind, status, message, output string
		var at time.Time
		if err := oldRows.Scan(&kind, &status, &message, &output, &at); err != nil {
			c.JSON(500, gin.H{"error": "failed to read legacy history"})
			return
		}
		old = append(old, gin.H{"kind": kind, "status": status, "error": message, "response": output, "finished_at": at})
	}
	if oldRows.Err() != nil {
		c.JSON(500, gin.H{"error": "failed to read legacy history"})
		return
	}
	c.JSON(200, gin.H{"rates": rates, "totals": totals, "items": items, "has_more": more, "legacy_runs": old})
}
func AdminUpdateModelRates(c *gin.Context) {
	var rates agent.ModelRates
	if err := c.ShouldBindJSON(&rates); err != nil {
		c.JSON(400, gin.H{"error": "invalid rates"})
		return
	}
	if rates.Unit != "tokens" && rates.Unit != "call" {
		c.JSON(400, gin.H{"error": "unit must be tokens or call"})
		return
	}
	for _, rate := range []*float64{rates.Input, rates.Output, rates.CacheRead, rates.CacheWrite, rates.Call} {
		if rate != nil && (math.IsNaN(*rate) || math.IsInf(*rate, 0) || *rate < 0 || *rate > 1e9) {
			c.JSON(400, gin.H{"error": "rates must be finite USD amounts between 0 and 1000000000"})
			return
		}
	}
	result, err := db.Get().ExecContext(c.Request.Context(), `INSERT INTO ai_model_rates(model_id,unit,input_usd,output_usd,cache_read_usd,cache_write_usd,call_usd) SELECT id,$2,$3,$4,$5,$6,$7 FROM ai_models WHERE id=$1 ON CONFLICT(model_id) DO UPDATE SET unit=EXCLUDED.unit,input_usd=EXCLUDED.input_usd,output_usd=EXCLUDED.output_usd,cache_read_usd=EXCLUDED.cache_read_usd,cache_write_usd=EXCLUDED.cache_write_usd,call_usd=EXCLUDED.call_usd,updated_at=CURRENT_TIMESTAMP`, c.Param("id"), rates.Unit, rates.Input, rates.Output, rates.CacheRead, rates.CacheWrite, rates.Call)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to save rates"})
		return
	}
	n, err := result.RowsAffected()
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to save rates"})
		return
	}
	if n == 0 {
		c.JSON(404, gin.H{"error": "model not found"})
		return
	}
	c.JSON(http.StatusOK, rates)
}

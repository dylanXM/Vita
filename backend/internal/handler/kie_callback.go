package handler

import (
	"github.com/gin-gonic/gin"
	"net/http"
	"strings"
	"vita/internal/agent"
)

// KieCallback never accepts result URLs or status as authoritative input.
func KieCallback(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64<<10)
	var input struct {
		Data struct {
			TaskID string `json:"taskId"`
		} `json:"data"`
	}
	if err := c.ShouldBindJSON(&input); err != nil || strings.TrimSpace(input.Data.TaskID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task callback"})
		return
	}
	agent.NotifyKieTask(input.Data.TaskID)
	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "success"})
}

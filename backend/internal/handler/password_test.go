package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestChangePasswordInput(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, item := range []struct {
		name, user, body string
		want             int
	}{
		{"no auth", "", `{"new_password":"abcdef"}`, http.StatusUnauthorized},
		{"short", "user", `{"new_password":"abc"}`, http.StatusBadRequest},
		{"malformed", "user", `{`, http.StatusBadRequest},
		{"too many bytes", "user", `{"new_password":"` + strings.Repeat("密", 25) + `"}`, http.StatusBadRequest},
	} {
		t.Run(item.name, func(t *testing.T) {
			router := gin.New()
			router.PUT("/", func(c *gin.Context) { c.Set("user_id", item.user); ChangeMyPassword(c) })
			req := httptest.NewRequest(http.MethodPut, "/", strings.NewReader(item.body))
			req.Header.Set("Content-Type", "application/json")
			res := httptest.NewRecorder()
			router.ServeHTTP(res, req)
			if res.Code != item.want {
				t.Fatalf("status %d, want %d", res.Code, item.want)
			}
		})
	}
}

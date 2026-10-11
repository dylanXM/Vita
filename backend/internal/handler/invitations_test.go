package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestBindInvitationRejectsMissingAuthAndInvalidInput(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, test := range []struct {
		name, user, body string
		status           int
	}{
		{"unauthenticated", "", `{"invite_code":"CODE"}`, http.StatusUnauthorized},
		{"empty", "user", `{"invite_code":"  "}`, http.StatusBadRequest},
		{"malformed", "user", `{`, http.StatusBadRequest},
		{"wrong type", "user", `{"invite_code":123}`, http.StatusBadRequest},
	} {
		t.Run(test.name, func(t *testing.T) {
			router := gin.New()
			router.POST("/", func(c *gin.Context) { c.Set("user_id", test.user); BindInvitation(c) })
			request := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(test.body))
			request.Header.Set("Content-Type", "application/json")
			result := httptest.NewRecorder()
			router.ServeHTTP(result, request)
			if result.Code != test.status {
				t.Fatalf("status = %d, want %d", result.Code, test.status)
			}
		})
	}
}

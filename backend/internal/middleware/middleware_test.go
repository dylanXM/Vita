package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestCORSAllowsConfiguredOriginAndRejectsOthers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(CORS([]string{"https://admin.example.com"}))
	engine.GET("/", func(c *gin.Context) { c.Status(http.StatusNoContent) })

	allowed := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	request.Header.Set("Origin", "https://admin.example.com")
	engine.ServeHTTP(allowed, request)
	if allowed.Code != http.StatusNoContent || allowed.Header().Get("Access-Control-Allow-Origin") != "https://admin.example.com" {
		t.Fatalf("configured origin response = %d, %q", allowed.Code, allowed.Header().Get("Access-Control-Allow-Origin"))
	}

	denied := httptest.NewRecorder()
	request = httptest.NewRequest(http.MethodGet, "/", nil)
	request.Header.Set("Origin", "https://attacker.example")
	engine.ServeHTTP(denied, request)
	if denied.Code != http.StatusForbidden {
		t.Fatalf("unconfigured origin status = %d; want %d", denied.Code, http.StatusForbidden)
	}
}

func TestRateLimitRejectsRequestsOverLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(RateLimit(1, time.Minute))
	engine.GET("/", func(c *gin.Context) { c.Status(http.StatusNoContent) })

	for attempt, want := range []int{http.StatusNoContent, http.StatusTooManyRequests} {
		response := httptest.NewRecorder()
		engine.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/", nil))
		if response.Code != want {
			t.Fatalf("attempt %d status = %d; want %d", attempt+1, response.Code, want)
		}
	}
}

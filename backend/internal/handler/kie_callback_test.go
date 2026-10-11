package handler

import (
	"github.com/gin-gonic/gin"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestKieCallback(t *testing.T) {
	router := gin.New()
	router.POST("/callback", KieCallback)
	for _, test := range []struct {
		body   string
		status int
	}{
		{`{"code":200,"data":{"taskId":"task1","resultJson":"untrusted"}}`, 200},
		{`{"data":{}}`, 400},
		{`invalid`, 400},
	} {
		req := httptest.NewRequest("POST", "/callback", strings.NewReader(test.body))
		req.Header.Set("Content-Type", "application/json")
		out := httptest.NewRecorder()
		router.ServeHTTP(out, req)
		if out.Code != test.status {
			t.Errorf("status=%d want=%d", out.Code, test.status)
		}
	}
}

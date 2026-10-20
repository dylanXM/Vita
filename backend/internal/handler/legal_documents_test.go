package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestLegalDocumentTypes(t *testing.T) {
	if !validLegalDocumentType("privacy") || !validLegalDocumentType("terms") {
		t.Fatal("privacy and terms must be valid legal document types")
	}
	if validLegalDocumentType("cookies") || validLegalDocumentType("") {
		t.Fatal("unsupported legal document types must be rejected")
	}
}

func TestWriteLegalAcceptanceError(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, test := range []struct {
		err    error
		status int
		code   string
	}{
		{errLegalConsentRequired, http.StatusBadRequest, "legal_consent_required"},
		{errLegalVersionChanged, http.StatusConflict, "legal_version_changed"},
		{errLegalUnavailable, http.StatusServiceUnavailable, "legal_documents_unavailable"},
	} {
		recorder := httptest.NewRecorder()
		context, _ := gin.CreateTestContext(recorder)
		writeLegalAcceptanceError(context, test.err)
		if recorder.Code != test.status || !strings.Contains(recorder.Body.String(), test.code) {
			t.Fatalf("error %q produced %d %s", test.err, recorder.Code, recorder.Body.String())
		}
	}
}

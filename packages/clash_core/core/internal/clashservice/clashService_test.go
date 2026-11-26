package clashservice

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func call(t *testing.T, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	recorder := httptest.NewRecorder()
	handleHTTP(recorder, httptest.NewRequest(method, path, nil))
	return recorder
}

func TestRouteAnswersTheApp(t *testing.T) {
	if response := call(t, http.MethodGet, "/"); response.Code != http.StatusOK {
		t.Fatalf("GET / -> %d", response.Code)
	}
	if response := call(t, http.MethodGet, "/version"); response.Code != http.StatusOK {
		t.Fatalf("GET /version -> %d", response.Code)
	} else if !strings.Contains(response.Body.String(), serviceVersion) {
		t.Fatalf("version body = %s", response.Body.String())
	}
	if response := call(t, http.MethodGet, "/clash/status"); response.Code != http.StatusOK {
		t.Fatalf("GET /clash/status -> %d", response.Code)
	}
}

func TestRouteRejectsWrongMethodAndUnknownPath(t *testing.T) {
	if response := call(t, http.MethodDelete, "/"); response.Code != http.StatusMethodNotAllowed {
		t.Fatalf("DELETE / -> %d", response.Code)
	}
	if response := call(t, http.MethodGet, "/nope"); response.Code != http.StatusNotFound {
		t.Fatalf("GET /nope -> %d", response.Code)
	}
}

func TestRouteHandlesEmptyProfileDir(t *testing.T) {
	// No core is running in this test, so the profile API falls back to the
	// request body's configDir; an empty one is a plain error, not a panic.
	if response := call(t, http.MethodGet, "/clash/schedule"); response.Code != http.StatusOK {
		t.Fatalf("GET /clash/schedule -> %d", response.Code)
	}
}

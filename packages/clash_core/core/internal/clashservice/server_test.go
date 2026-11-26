package clashservice

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"os"
	"testing"
)

func tunnelRequest(t *testing.T, dir, method, path string, body any) (int, map[string]any) {
	t.Helper()
	var payload io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("encode body: %v", err)
		}
		payload = bytes.NewReader(encoded)
	}
	client := &http.Client{Transport: &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			var dialer net.Dialer
			return dialer.DialContext(ctx, "unix", SocketPath(dir))
		},
	}}
	request, err := http.NewRequest(method, "http://localhost"+path, payload)
	if err != nil {
		t.Fatalf("build %s %s: %v", method, path, err)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer response.Body.Close()
	raw, _ := io.ReadAll(response.Body)
	var envelope map[string]any
	if err := json.Unmarshal(raw, &envelope); err != nil {
		t.Fatalf("decode %s %s: %v (%s)", method, path, err, raw)
	}
	return response.StatusCode, envelope
}

func TestServeTunnelServesTheControlAPI(t *testing.T) {
	dir := t.TempDir()
	applied := 0
	server, err := ServeTunnel(dir, func(string) error {
		applied++
		return nil
	})
	if err != nil {
		t.Fatalf("serve tunnel: %v", err)
	}
	defer server.Close()

	if status, envelope := tunnelRequest(t, dir, http.MethodGet, "/clash/status", nil); status != http.StatusOK || envelope["data"] != true {
		t.Fatalf("GET /clash/status -> %d %v", status, envelope)
	}

	// The app starts the tunnel, so the API refuses the lifecycle routes.
	if _, envelope := tunnelRequest(t, dir, http.MethodPost, "/clash/vpn/start", map[string]any{"configDir": dir}); envelope["code"] != float64(apiErrorCode) {
		t.Fatalf("POST /clash/vpn/start should be refused: %v", envelope)
	}

	// A schedule written through the API is what the in-process timer reads.
	_, envelope := tunnelRequest(t, dir, http.MethodPost, "/clash/profile?refresh=false", map[string]any{
		"configDir":      dir,
		"url":            "http://127.0.0.1/sub",
		"updateInterval": 60,
	})
	if envelope["code"] != float64(0) {
		t.Fatalf("POST /clash/profile -> %v", envelope)
	}
	if _, schedule := tunnelRequest(t, dir, http.MethodGet, "/clash/schedule", nil); schedule["data"].(map[string]any)["scheduled"] != true {
		t.Fatalf("GET /clash/schedule -> %v", schedule)
	}

	// /clash/reload hot-applies the config the app just wrote.
	if _, reload := tunnelRequest(t, dir, http.MethodPost, "/clash/reload", nil); reload["code"] != float64(0) {
		t.Fatalf("POST /clash/reload -> %v", reload)
	}
	if applied == 0 {
		t.Fatal("reload did not apply the config")
	}

	server.Close()
	if _, err := os.Stat(SocketPath(dir)); !os.IsNotExist(err) {
		t.Fatalf("socket still there after Close: %v", err)
	}
}

//go:build darwin || linux || windows

package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"go.yaml.in/yaml/v3"
)

func TestNextUpdateDelay(t *testing.T) {
	now := time.Date(2026, 11, 25, 12, 0, 0, 0, time.Local)

	neverDownloaded := &clashProfile{UpdateInterval: 60}
	if _, ok := neverDownloaded.nextUpdateDelay(now); ok {
		t.Fatal("a profile without updateTime must not be scheduled")
	}

	disabled := &clashProfile{UpdateInterval: 0, UpdateTime: dartLocalTime(now)}
	if _, ok := disabled.nextUpdateDelay(now); ok {
		t.Fatal("a profile without an interval must not be scheduled")
	}

	due := &clashProfile{UpdateInterval: 60, UpdateTime: dartLocalTime(now.Add(-2 * time.Hour))}
	delay, ok := due.nextUpdateDelay(now)
	if !ok || delay != minUpdateDelay {
		t.Fatalf("an overdue profile must wait %v, got %v (scheduled %v)", minUpdateDelay, delay, ok)
	}

	future := &clashProfile{UpdateInterval: 60, UpdateTime: dartLocalTime(now.Add(-5 * time.Minute))}
	delay, ok = future.nextUpdateDelay(now)
	if !ok || delay != 55*time.Minute {
		t.Fatalf("expected a 55m delay, got %v (scheduled %v)", delay, ok)
	}
}

func TestParseProfile(t *testing.T) {
	if parseProfile(`/tmp/clashy/config`) != nil {
		t.Fatal("a plain string must not parse into a profile")
	}
	if parseProfile("") != nil {
		t.Fatal("an empty string must not parse into a profile")
	}

	profile := parseProfile(map[string]any{
		"configDir":      "/tmp/clashy/config",
		"name":           "subscription",
		"url":            "https://example.com/sub",
		"updateInterval": float64(120),
		"updateTime":     "2026-11-25T10:00:00.000",
	})
	if profile == nil {
		t.Fatal("a JSON profile was not parsed")
	}
	if profile.UpdateInterval != 120 {
		t.Fatalf("updateInterval was not parsed: %d", profile.UpdateInterval)
	}
	if _, ok := parseProfileTime(profile.UpdateTime); !ok {
		t.Fatalf("updateTime was not parsed: %q", profile.UpdateTime)
	}

	if parseProfile(nil) != nil {
		t.Fatal("a missing body must not parse into a profile")
	}
}

func TestClashProfileJSONShape(t *testing.T) {
	payload := `{"id":null,"name":"sub","url":null,"configDir":"/tmp/c","updateInterval":null,"updateTime":null,"script":null}`
	profile := parseProfile(map[string]any{
		"id":             nil,
		"name":           "sub",
		"url":            nil,
		"configDir":      "/tmp/c",
		"updateInterval": nil,
		"updateTime":     nil,
		"script":         nil,
	})
	if profile == nil {
		t.Fatalf("null-filled profile was not parsed: %s", payload)
	}
	if profile.Name != "sub" || profile.ConfigDir != "/tmp/c" {
		t.Fatalf("unexpected profile: %+v", profile)
	}
	if strings.TrimSpace(profile.URL) != "" {
		t.Fatalf("a null url must stay empty, got %q", profile.URL)
	}
}

func TestRefreshConfigMergesAndKeepsBackupRemoved(t *testing.T) {
	subscription := "mixed-port: 9999\nproxies:\n  - name: node\n    type: direct\n"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(subscription))
	}))
	defer server.Close()

	configDir := t.TempDir()
	configPath := filepath.Join(configDir, configFileName)
	appConfig := "mixed-port: 7890\ntun:\n  enable: true\n"
	if err := os.WriteFile(configPath, []byte(appConfig), 0o644); err != nil {
		t.Fatalf("write app config: %v", err)
	}

	profile := &clashProfile{ConfigDir: configDir, URL: server.URL}
	runtime := &coreRuntime{}
	if err := runtime.refreshConfig(profile); err != nil {
		t.Fatalf("refreshConfig: %v", err)
	}

	payload, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read merged config: %v", err)
	}
	var merged map[string]any
	if err := yaml.Unmarshal(payload, &merged); err != nil {
		t.Fatalf("merged config is not YAML: %v\n%s", err, payload)
	}
	if merged["mixed-port"] != 7890 {
		t.Fatalf("app-owned mixed-port was overwritten:\n%s", payload)
	}
	if _, ok := merged["proxies"]; !ok {
		t.Fatalf("subscription content was not written:\n%s", payload)
	}
	if _, err := os.Stat(configPath + ".bak"); !os.IsNotExist(err) {
		t.Fatalf("backup file must be removed after a successful update: %v", err)
	}
}

func TestRefreshConfigRequiresURLAndConfigFile(t *testing.T) {
	configDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(configDir, configFileName), []byte("mode: rule\n"), 0o644); err != nil {
		t.Fatalf("write app config: %v", err)
	}

	runtime := &coreRuntime{}
	if err := runtime.refreshConfig(&clashProfile{ConfigDir: configDir}); err == nil {
		t.Fatal("expected an error for a profile without a url")
	}
	if err := runtime.refreshConfig(&clashProfile{ConfigDir: t.TempDir(), URL: "http://127.0.0.1:1/sub"}); err == nil {
		t.Fatal("expected an error for a missing config file")
	}
}

func TestIsNumericSID(t *testing.T) {
	valid := []string{
		"S-1-5-21-1234567890-1234567890-1234567890-1001",
		"S-1-5-18",
	}
	for _, value := range valid {
		if !isNumericSID(value) {
			t.Fatalf("expected %q to be a numeric SID", value)
		}
	}
	invalid := []string{
		"",
		"S-1-5-",
		"S-1-5-21-x",
		"S-1-5-21-(A;;GA;;;BA)",
		"BU",
	}
	for _, value := range invalid {
		if isNumericSID(value) {
			t.Fatalf("expected %q to be rejected", value)
		}
	}
}

func TestEnsureConfigFileRejectsSymlink(t *testing.T) {
	configDir := t.TempDir()
	target := filepath.Join(configDir, "real.yaml")
	if err := os.WriteFile(target, []byte("mode: rule\n"), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	if err := os.Symlink(target, filepath.Join(configDir, configFileName)); err == nil {
		if err := ensureConfigFile(configDir); err == nil {
			t.Fatal("expected a symlinked config file to be rejected")
		}
	}
	if err := os.RemoveAll(filepath.Join(configDir, configFileName)); err != nil {
		t.Fatalf("remove config: %v", err)
	}
	if err := ensureConfigFile(configDir); err == nil {
		t.Fatal("expected a missing config file to be rejected")
	}
}

func TestEnsureConfigFileAcceptsRegularFile(t *testing.T) {
	configDir := t.TempDir()
	path := filepath.Join(configDir, configFileName)
	if err := os.WriteFile(path, []byte("mode: rule\n"), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	if err := ensureConfigFile(configDir); err != nil {
		t.Fatalf("expected a regular config file to be accepted: %v", err)
	}
}

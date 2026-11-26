package profilerefresh

import (
	"testing"

	"go.yaml.in/yaml/v3"
)

func TestApplyConfigOverridesKeepsAppOwnedKeys(t *testing.T) {
	current := `mixed-port: 7890
mode: global
tun:
  enable: true
  stack: gvisor
dns:
  enable: true
  nameserver:
    - 223.5.5.5
`
	downloaded := `mixed-port: 9999
mode: rule
proxies:
  - name: node
    type: direct
`
	merged, err := applyOverrides(downloaded, current)
	if err != nil {
		t.Fatalf("ApplyOverrides: %v", err)
	}

	var result map[string]any
	if err := yaml.Unmarshal([]byte(merged), &result); err != nil {
		t.Fatalf("merged config is not YAML: %v\n%s", err, merged)
	}

	if result["mixed-port"] != 7890 {
		t.Fatalf("mixed-port was not kept from the app config: %v", result["mixed-port"])
	}
	if result["mode"] != "global" {
		t.Fatalf("mode was not kept from the app config: %v", result["mode"])
	}
	if _, ok := result["proxies"]; !ok {
		t.Fatalf("subscription proxies were dropped:\n%s", merged)
	}
	tun, ok := result["tun"].(map[string]any)
	if !ok || tun["enable"] != true {
		t.Fatalf("tun section was not kept from the app config: %v", result["tun"])
	}
}

func TestApplyConfigOverridesRejectsNonMapSubscription(t *testing.T) {
	if _, err := applyOverrides("- just\n- a list\n", "mode: global\n"); err == nil {
		t.Fatal("expected an error for a subscription that is not a YAML map")
	}
}

func TestApplyConfigOverridesIgnoresUnparsableCurrentConfig(t *testing.T) {
	downloaded := "mode: rule\n"
	merged, err := applyOverrides(downloaded, "\tmode: [unclosed\n")
	if err != nil {
		t.Fatalf("ApplyOverrides: %v", err)
	}
	if merged != downloaded {
		t.Fatalf("expected the downloaded config untouched, got:\n%s", merged)
	}
}

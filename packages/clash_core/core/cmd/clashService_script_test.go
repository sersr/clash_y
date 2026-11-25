package main

import (
	"strings"
	"testing"
	"time"
)

const scriptTestConfig = `proxies:
    - name: a
      type: ss
    - name: b
      type: ss
proxy-groups:
    - name: G
      type: select
      proxies: [a, b]
log-level: info
`

// Every platform takes the object main() returns; a JSON string is a mistake
// that must fail here too, otherwise only Go would accept the script.
func TestRunProfileScriptRejectsJSONString(t *testing.T) {
	script := `
function main(config) {
  return JSON.stringify(config);
}`
	if got := runProfileScript(scriptTestConfig, script); got != scriptTestConfig {
		t.Fatalf("a JSON string return was accepted:\n%s", got)
	}
}

func TestRunProfileScriptFiltersProxies(t *testing.T) {
	script := `
function main(config) {
  config.proxies = config.proxies.filter((p) => p.name !== "b");
  config["proxy-groups"][0].proxies = config.proxies.map((p) => p.name);
  return config;
}`

	result := runProfileScript(scriptTestConfig, script)
	if strings.Contains(result, "name: b") {
		t.Fatalf("script did not drop proxy b:\n%s", result)
	}
	if !strings.Contains(result, "proxies:\n    - name: a\n      type: ss\n") {
		t.Fatalf("script lost the kept proxy:\n%s", result)
	}
	if !strings.Contains(result, "proxies:\n        - a\n") {
		t.Fatalf("script did not rewrite the group:\n%s", result)
	}
	if !strings.Contains(result, "log-level: info") {
		t.Fatalf("script lost an untouched key:\n%s", result)
	}
	if strings.HasPrefix(strings.TrimSpace(result), "{") {
		t.Fatalf("script output is not block YAML:\n%s", result)
	}
}

// The Dart app exposes the config as the global `profileConfig` before the
// script runs, so a script may use it without main()'s argument.
func TestRunProfileScriptExposesGlobalConfig(t *testing.T) {
	script := `
function main() {
  profileConfig.mode = "direct";
  return profileConfig;
}`
	result := runProfileScript(scriptTestConfig, script)
	if !strings.Contains(result, "mode: direct") {
		t.Fatalf("global profileConfig was not visible:\n%s", result)
	}
}

func TestRunProfileScriptKeepsScalarTypes(t *testing.T) {
	script := `function main(config) { return config; }`
	config := "mixed-port: 7890\nallow-lan: true\nsecret: \"\"\ntolerance: 0.5\nname: \"1.2.3\"\n"
	got := runProfileScript(config, script)
	for _, want := range []string{
		"mixed-port: 7890\n",
		"allow-lan: true\n",
		"secret: \"\"\n",
		"tolerance: 0.5\n",
		"name: 1.2.3\n",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("scalar round trip lost %q:\n%s", want, got)
		}
	}
}

// Android stringifies the object main() returns, so accepting both shapes keeps
// one script working on every platform.
func TestRunProfileScriptReturnsObject(t *testing.T) {
	script := `
function main(config) {
  return { ...config, mode: "direct" };
}`
	result := runProfileScript(scriptTestConfig, script)
	if !strings.Contains(result, "mode: direct") {
		t.Fatalf("script return object was ignored:\n%s", result)
	}
	if !strings.Contains(result, "name: a") {
		t.Fatalf("spread copy lost the proxies:\n%s", result)
	}
}

// Subscription refresh runs the script first and then restores the app-owned
// keys, so a script cannot flip the user's mode or port switches.
func TestProfileScriptRunsBeforeAppOverrides(t *testing.T) {
	download := "mode: rule\nmixed-port: 7890\nproxies: []\n"
	script := `function main(config) {
  config.mode = "direct";
  config["mixed-port"] = 1234;
  config["scripted-key"] = true;
  return config;
}`
	scripted := runProfileScript(download, script)
	merged, err := applyConfigOverrides(scripted, "mode: global\nmixed-port: 4321\n")
	if err != nil {
		t.Fatalf("apply overrides: %v", err)
	}
	for _, want := range []string{"mode: global\n", "mixed-port: 4321\n", "scripted-key: true\n"} {
		if !strings.Contains(merged, want) {
			t.Fatalf("missing %q in merged config:\n%s", want, merged)
		}
	}
}

// Real profile scripts lean on ES2015+ features; this pins the engine's
// feature set so a future engine change cannot silently degrade it.
func TestRunProfileScriptSupportsModernSyntax(t *testing.T) {
	script := "const rename = (proxy, index = 0) => {\n" +
		"  const { name, ...rest } = proxy;\n" +
		"  return { ...rest, name: `${index + 1}-${name}` };\n" +
		"};\n" +
		"function main(config) {\n" +
		"  const first = config.proxies?.[0];\n" +
		"  config.proxies = config.proxies.map(rename);\n" +
		"  config.note = first ? `seen ${first.name}` : \"none\";\n" +
		"  return config;\n" +
		"}"
	result := runProfileScript(scriptTestConfig, script)
	if !strings.Contains(result, "name: 1-a\n") {
		t.Fatalf("arrow/destructuring/template literal did not run:\n%s", result)
	}
	if !strings.Contains(result, "note: seen a\n") {
		t.Fatalf("optional chaining did not run:\n%s", result)
	}
}

func TestRunProfileScriptKeepsConfigOnFailure(t *testing.T) {
	cases := map[string]string{
		"syntax error":     `function main(config) { return config; `,
		"throws":           `function main() { throw new Error("boom"); }`,
		"no main":          `var something = 1;`,
		"undefined result": `function main(config) {}`,
		"json string":      `function main() { return "not json"; }`,
		"array return":     `function main() { return []; }`,
		"number return":    `function main() { return 42; }`,
	}
	for name, script := range cases {
		got := runProfileScript(scriptTestConfig, script)
		if got != scriptTestConfig {
			t.Errorf("%s: config changed by a failing script:\n%s", name, got)
		}
	}
}

func TestRunProfileScriptWithoutScript(t *testing.T) {
	for _, script := range []string{"", "   \n\t"} {
		if got := runProfileScript(scriptTestConfig, script); got != scriptTestConfig {
			t.Errorf("blank script changed the config:\n%s", got)
		}
	}
}

func TestRunProfileScriptRejectsNonMapConfig(t *testing.T) {
	if got := runProfileScript("- a\n", `function main(c) { return c; }`); got != "- a\n" {
		t.Fatalf("non-map config was not kept:\n%s", got)
	}
}

func TestRunProfileScriptTimesOut(t *testing.T) {
	previous := scriptTimeout
	scriptTimeout = 50 * time.Millisecond
	defer func() { scriptTimeout = previous }()

	started := time.Now()
	got := runProfileScript(scriptTestConfig, `function main(c) { while (true) {} }`)
	if got != scriptTestConfig {
		t.Fatalf("timed out script changed the config:\n%s", got)
	}
	if elapsed := time.Since(started); elapsed > 5*time.Second {
		t.Fatalf("script interrupt took %s", elapsed)
	}
}

func TestRunProfileScriptIgnoresOversizedScript(t *testing.T) {
	script := "function main(c) { return JSON.stringify(c); }" + strings.Repeat(" ", maxScriptSize)
	if got := runProfileScript(scriptTestConfig, script); got != scriptTestConfig {
		t.Fatalf("oversized script was executed")
	}
}

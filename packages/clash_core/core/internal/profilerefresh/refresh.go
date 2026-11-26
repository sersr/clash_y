// Package profilerefresh downloads a subscription and turns it into the
// config.yaml the core runs.
//
// It is shared by every place that refreshes a profile without the Dart app in
// the loop: the desktop daemon, the Android VPN service and the iOS Packet
// Tunnel extension. Keeping one implementation guarantees a background refresh
// produces the same file as a refresh started from the app.
package profilerefresh

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/dop251/goja"
	"go.yaml.in/yaml/v3"
)

const (
	// requestTimeout bounds a subscription download.
	requestTimeout = 15 * time.Second
	// userAgent is the one providers expect from Clash clients.
	userAgent = "clash/mihomo"
	// maxSubscriptionSize guards against runaway payloads.
	maxSubscriptionSize = 32 << 20
	// maxScriptSize is a second guard on top of the bounded profile payload.
	maxScriptSize = 256 << 10
)

// scriptTimeout bounds a profile script: a runaway loop must not hang the
// process that owns the tunnel. A var so tests can shorten it.
var scriptTimeout = 5 * time.Second

// overrideKeys are the top-level keys owned by the app.
//
// The app writes device-specific settings (ports, TUN, DNS, controller socket
// ...) and GeoX CDN URLs into config.yaml; subscription updates must keep those
// values instead of whatever the provider ships. Keep this list in sync with
// ProfileExt._updateProfileData in packages/common/lib/src/data/profile.dart,
// the only place the app writes these keys.
var overrideKeys = []string{
	"external-controller-unix",
	"external-controller-pipe",
	"log-level",
	"mixed-port",
	"mode",
	"ipv6",
	"allow-lan",
	"tun",
	"dns",
	"geox-url",
}

// download fetches a subscription body.
func download(url string) (string, error) {
	if strings.TrimSpace(url) == "" {
		return "", errors.New("profile url is empty")
	}

	transport := &http.Transport{
		DialContext: (&net.Dialer{Timeout: requestTimeout}).DialContext,
	}
	client := &http.Client{Transport: transport}
	defer client.CloseIdleConnections()

	request, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return "", fmt.Errorf("create subscription request: %w", err)
	}
	request.Header.Set("User-Agent", userAgent)

	response, err := client.Do(request)
	if err != nil {
		return "", fmt.Errorf("download subscription: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode >= http.StatusBadRequest {
		return "", fmt.Errorf("download subscription: unexpected status %s", response.Status)
	}

	payload, err := io.ReadAll(io.LimitReader(response.Body, maxSubscriptionSize))
	if err != nil {
		return "", fmt.Errorf("read subscription: %w", err)
	}
	return string(payload), nil
}

// Refresh downloads url, applies script and keeps the app-owned keys of
// current.
//
// The script runs on the downloaded config first, then the app-owned keys are
// applied on top: the app's own settings must win over anything the script
// produced, which is the order the Dart client uses.
func Refresh(url string, script string, current string) (string, error) {
	downloaded, err := download(url)
	if err != nil {
		return "", err
	}
	return merge(downloaded, script, current)
}

// merge applies script to downloaded and then overlays the app-owned keys of
// current.
func merge(downloaded string, script string, current string) (string, error) {
	scripted := RunScript(downloaded, script)
	return applyOverrides(scripted, current)
}

// RunScript applies the profile JavaScript to configText, mirroring the Dart
// app, the only other place that runs a profile script:
//
//	const profileConfig = <config as JSON>
//	<script>
//	main(profileConfig) -> the config object
//
// Any failure keeps the untouched config: a broken script must not silently
// produce a different running configuration.
func RunScript(configText string, script string) string {
	if strings.TrimSpace(script) == "" {
		return configText
	}
	if len(script) > maxScriptSize {
		return configText
	}

	out, err := evaluateScript(configText, script)
	if err != nil {
		return configText
	}
	return out
}

func evaluateScript(configText string, script string) (result string, err error) {
	defer func() {
		// A JS engine bug must not take the whole process down.
		if recovered := recover(); recovered != nil {
			result = ""
			err = fmt.Errorf("profile script panicked: %v", recovered)
		}
	}()

	var configMap map[string]any
	if unmarshalErr := yaml.Unmarshal([]byte(configText), &configMap); unmarshalErr != nil {
		return "", fmt.Errorf("parse config before running the profile script: %w", unmarshalErr)
	}
	if configMap == nil {
		return "", errors.New("config is not a YAML map")
	}

	payload, marshalErr := json.Marshal(configMap)
	if marshalErr != nil {
		return "", fmt.Errorf("encode config for the profile script: %w", marshalErr)
	}

	vm := goja.New()
	timer := time.AfterFunc(scriptTimeout, func() {
		vm.Interrupt("profile script exceeded its time limit")
	})
	defer timer.Stop()

	// The script sees the config as the global `profileConfig` and receives it
	// as main()'s argument, like the Dart app.
	quoted := strconv.Quote(string(payload))
	if _, err := vm.RunString("var profileConfig = JSON.parse(" + quoted + ");"); err != nil {
		return "", fmt.Errorf("parse config inside the profile script: %w", err)
	}
	if _, err := vm.RunString(script); err != nil {
		return "", fmt.Errorf("evaluate profile script: %w", err)
	}

	mainValue := vm.Get("main")
	mainFunc, ok := goja.AssertFunction(mainValue)
	if !ok {
		return "", errors.New("profile script does not define main(config)")
	}
	value, err := mainFunc(goja.Undefined(), vm.Get("profileConfig"))
	if err != nil {
		return "", fmt.Errorf("run main(profileConfig): %w", err)
	}
	if goja.IsUndefined(value) || goja.IsNull(value) {
		return "", errors.New("profile script returned no config")
	}

	// Every platform takes the returned config object: returning a JSON string
	// is a mistake that must fail here too instead of only on one client.
	exported := value.Export()
	output, isObject := exported.(map[string]any)
	if !isObject {
		if _, isString := exported.(string); isString {
			return "", errors.New("profile script must return the config object, not a JSON string")
		}
		return "", fmt.Errorf("profile script must return the config object, got %T", exported)
	}
	raw, marshalErr := json.Marshal(output)
	if marshalErr != nil {
		return "", fmt.Errorf("encode the config returned by the profile script: %w", marshalErr)
	}
	decoded, err := decodeScriptConfig(raw)
	if err != nil {
		return "", err
	}

	encoded, err := yaml.Marshal(decoded)
	if err != nil {
		return "", fmt.Errorf("encode scripted config: %w", err)
	}
	return string(encoded), nil
}

// decodeScriptConfig parses the JSON the profile script returned into the map
// yaml.Marshal expects. Numbers go through json.Number so a port keeps its
// integer type instead of becoming a float (or a quoted string).
func decodeScriptConfig(payload []byte) (map[string]any, error) {
	decoder := json.NewDecoder(bytes.NewReader(payload))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		return nil, fmt.Errorf("profile script returned invalid JSON: %w", err)
	}
	object, ok := value.(map[string]any)
	if !ok {
		if value == nil {
			return nil, errors.New("profile script returned no config")
		}
		return nil, fmt.Errorf("profile script must return a config map, got %T", value)
	}
	if len(object) == 0 {
		return nil, errors.New("profile script returned an empty config")
	}
	converted, _ := convertJSONNumbers(object).(map[string]any)
	return converted, nil
}

func convertJSONNumbers(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		for key, child := range typed {
			typed[key] = convertJSONNumbers(child)
		}
		return typed
	case []any:
		for index, child := range typed {
			typed[index] = convertJSONNumbers(child)
		}
		return typed
	case json.Number:
		if integer, err := typed.Int64(); err == nil {
			return integer
		}
		if decimal, err := typed.Float64(); err == nil {
			return decimal
		}
		return typed.String()
	default:
		return value
	}
}

// ApplyOverrides keeps the app-owned top-level keys of current in downloaded.
func applyOverrides(downloaded string, current string) (string, error) {
	var currentDoc yaml.Node
	if err := yaml.Unmarshal([]byte(current), &currentDoc); err != nil {
		return downloaded, nil
	}
	currentMapping := documentMapping(&currentDoc)
	if currentMapping == nil {
		return downloaded, nil
	}

	var downloadedDoc yaml.Node
	if err := yaml.Unmarshal([]byte(downloaded), &downloadedDoc); err != nil {
		return "", errors.New("downloaded config is not a YAML map")
	}
	downloadedMapping := documentMapping(&downloadedDoc)
	if downloadedMapping == nil {
		return "", errors.New("downloaded config is not a YAML map")
	}

	for _, key := range overrideKeys {
		value := mappingValue(currentMapping, key)
		if value == nil {
			continue
		}
		replaceMappingValue(downloadedMapping, key, value)
	}

	payload, err := yaml.Marshal(&downloadedDoc)
	if err != nil {
		return "", fmt.Errorf("write merged config: %w", err)
	}
	return string(payload), nil
}

func documentMapping(document *yaml.Node) *yaml.Node {
	if document.Kind == yaml.DocumentNode && len(document.Content) > 0 {
		mapping := document.Content[0]
		if mapping.Kind == yaml.MappingNode {
			return mapping
		}
	}
	return nil
}

func mappingValue(mapping *yaml.Node, key string) *yaml.Node {
	for index := 0; index+1 < len(mapping.Content); index += 2 {
		if mapping.Content[index].Value == key {
			return mapping.Content[index+1]
		}
	}
	return nil
}

func replaceMappingValue(mapping *yaml.Node, key string, value *yaml.Node) {
	for index := 0; index+1 < len(mapping.Content); index += 2 {
		if mapping.Content[index].Value == key {
			mapping.Content[index+1] = cloneNode(value)
			return
		}
	}
	keyNode := &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: key}
	mapping.Content = append(mapping.Content, keyNode, cloneNode(value))
}

func cloneNode(node *yaml.Node) *yaml.Node {
	if node == nil {
		return nil
	}
	copied := *node
	copied.Content = make([]*yaml.Node, len(node.Content))
	for index, child := range node.Content {
		copied.Content[index] = cloneNode(child)
	}
	return &copied
}

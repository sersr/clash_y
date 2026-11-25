package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/dop251/goja"
	"go.yaml.in/yaml/v3"
)

// scriptTimeout bounds a profile script. It runs inside a privileged daemon
// during subscription refresh, so a runaway loop must not block the API.
var scriptTimeout = 5 * time.Second

// maxScriptSize keeps a posted profile from stuffing an enormous script into
// the daemon; profile payloads are bounded anyway, this is a second guard.
const maxScriptSize = 256 << 10

// runProfileScript applies the profile JavaScript to configText, mirroring the
// Dart app and the Android updater:
//
//	const profileConfig = <config as JSON>
//	<script>
//	main(profileConfig) -> the config object
//
// Any failure keeps the untouched config: a broken script must not silently
// produce a different running configuration.
func runProfileScript(configText string, script string) string {
	if strings.TrimSpace(script) == "" {
		return configText
	}
	if len(script) > maxScriptSize {
		logf("profile script is larger than %d bytes; ignoring it", maxScriptSize)
		return configText
	}

	out, err := evaluateProfileScript(configText, script)
	if err != nil {
		logf("profile script failed; keeping the unmodified config: %v", err)
		return configText
	}
	return out
}

func evaluateProfileScript(configText string, script string) (result string, err error) {
	defer func() {
		// A JS engine bug must not take the whole daemon down.
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
	// as main()'s argument, like the Dart and Android implementations.
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


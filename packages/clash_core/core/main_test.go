package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
)

// TestSetHomeDirReadsConfigDir guards the "-d configDir" contract.
func TestSetHomeDirReadsConfigDir(t *testing.T) {
	dir := t.TempDir()

	cfgPath := filepath.Join(dir, configFileName)
	if err := os.WriteFile(cfgPath, []byte("mixed-port: 1234\nlog-level: silent\n"), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	if err := setHomeDir(dir); err != nil {
		t.Fatalf("setHomeDir: %v", err)
	}

	cfg, err := executor.Parse()
	if err != nil {
		t.Fatalf("parse config from configDir: %v", err)
	}

	if cfg.General.MixedPort != 1234 {
		t.Fatalf("expected mixed-port 1234, got %d", cfg.General.MixedPort)
	}
}

func TestBuildFdTunOptionsForAndroid(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, configFileName)
	if err := os.WriteFile(
		cfgPath,
		[]byte("tun:\n  auto-detect-interface: true\n"),
		0o644,
	); err != nil {
		t.Fatalf("write config: %v", err)
	}
	if err := setHomeDir(dir); err != nil {
		t.Fatalf("setHomeDir: %v", err)
	}

	cfg, err := executor.Parse()
	if err != nil {
		t.Fatalf("parse config from configDir: %v", err)
	}
	options := buildFdTunOptions(cfg, 42, "android")
	if !options.Enable || options.AutoRoute || options.AutoDetectInterface {
		t.Fatalf("unexpected Android TUN options: %+v", options)
	}
	if options.MTU != 9000 {
		t.Fatalf("expected Android VPN MTU 9000, got %d", options.MTU)
	}
	if options.FileDescriptor != 42 {
		t.Fatalf("expected VpnService fd 42, got %d", options.FileDescriptor)
	}
}

func TestBuildFdTunOptionsForIOS(t *testing.T) {
	tests := []struct {
		name      string
		config    string
		wantStack constant.TUNStack
	}{
		{
			name:      "mips stack",
			config:    "tun:\n  stack: mips\n",
			wantStack: constant.TunMips,
		},
		{
			name:      "gVisor stack",
			config:    "tun:\n  stack: gvisor\n",
			wantStack: constant.TunGvisor,
		},
		{
			name:      "system stack",
			config:    "tun:\n  stack: system\n",
			wantStack: constant.TunSystem,
		},
		{
			name:      "mixed stack",
			config:    "tun:\n  stack: mixed\n",
			wantStack: constant.TunMixed,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			cfgPath := filepath.Join(dir, configFileName)
			if err := os.WriteFile(cfgPath, []byte(tt.config), 0o644); err != nil {
				t.Fatalf("write config: %v", err)
			}
			if err := setHomeDir(dir); err != nil {
				t.Fatalf("setHomeDir: %v", err)
			}

			cfg, err := executor.Parse()
			if err != nil {
				t.Fatalf("parse config from configDir: %v", err)
			}
			options := buildFdTunOptions(cfg, 42, "ios")
			if options.Stack != tt.wantStack {
				t.Fatalf("expected iOS stack %s, got %s", tt.wantStack, options.Stack)
			}
			if options.MTU != 1500 {
				t.Fatalf("expected iOS packet-flow MTU 1500, got %d", options.MTU)
			}
			if !options.AutoDetectInterface {
				t.Fatal("expected iOS to preserve automatic interface detection")
			}
			if options.FileDescriptor != 42 {
				t.Fatalf("expected packet-flow fd 42, got %d", options.FileDescriptor)
			}
		})
	}
}

// TestSetHomeDirRejectsEmptyDir documents the error returned for start("").
func TestSetHomeDirRejectsEmptyDir(t *testing.T) {
	if err := setHomeDir(""); err == nil {
		t.Fatal("expected an error for an empty config dir")
	}
}

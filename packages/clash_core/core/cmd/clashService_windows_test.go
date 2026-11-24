//go:build windows

package main

import "testing"

func TestServiceStatePattern(t *testing.T) {
	output := `
SERVICE_NAME: clashy_tun_helper
        TYPE               : 10  WIN32_OWN_PROCESS
        STATE              : 4  RUNNING
                                (STOPPABLE, NOT_PAUSABLE, ACCEPTS_SHUTDOWN)
        WIN32_EXIT_CODE    : 0  (0x0)
`
	match := serviceStatePattern.FindStringSubmatch(output)
	if match == nil {
		t.Fatal("STATE line was not parsed")
	}
	if match[1] != "4" {
		t.Fatalf("expected state 4, got %q", match[1])
	}
}

func TestServiceBinPathPattern(t *testing.T) {
	output := `
SERVICE_NAME: clashy_tun_helper
        TYPE               : 10  WIN32_OWN_PROCESS
        START_TYPE         : 2   AUTO_START
        BINARY_PATH_NAME   : "C:\Program Files\Clashy\clashyTunHelper.exe"
`
	match := serviceBinPathPattern.FindStringSubmatch(output)
	if match == nil {
		t.Fatal("BINARY_PATH_NAME line was not parsed")
	}
	if match[1] != `"C:\Program Files\Clashy\clashyTunHelper.exe"` {
		t.Fatalf("unexpected bin path: %q", match[1])
	}
}

func TestSameWindowsPath(t *testing.T) {
	expected := `C:\Program Files\Clashy\clashyTunHelper.exe`
	cases := []struct {
		current string
		same    bool
	}{
		{`"C:\Program Files\Clashy\clashyTunHelper.exe"`, true},
		{`C:\Program Files\Clashy\clashyTunHelper.exe`, true},
		{`c:\program files\clashy\clashytunhelper.exe`, true},
		{`C:\Program Files\Clashy\clashyService.exe`, false},
	}
	for _, testCase := range cases {
		if got := sameWindowsPath(testCase.current, expected); got != testCase.same {
			t.Fatalf("sameWindowsPath(%q) = %v, want %v", testCase.current, got, testCase.same)
		}
	}
}

// 本地化的 sc 输出是控制台代码页字节，进入 API 错误或日志前必须去掉读不出来的
// 部分，只留下可读 ASCII 与 Win32 错误码。
func TestSCDetailsDropsNonASCII(t *testing.T) {
	cases := []struct {
		output string
		want   string
	}{
		{"", ""},
		{"   ", ""},
		{"[SC] OpenSCManager 失败 5:\r\n\r\n拒绝访问。", ": [SC] OpenSCManager 5:"},
		{"     [SC]     DeleteService      FAILED     1060:\n", ": [SC] DeleteService FAILED 1060:"},
	}
	for _, testCase := range cases {
		if got := scDetails(testCase.output); got != testCase.want {
			t.Fatalf("scDetails(%q) = %q, want %q", testCase.output, got, testCase.want)
		}
	}
}

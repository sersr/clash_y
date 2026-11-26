package profileschedule

import (
	"testing"
	"time"
)

func TestDelayUsesTheInterval(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	last := now.Add(-60 * time.Second)

	delay, ok := Delay(now, last, 10, SettleDelay)
	if !ok {
		t.Fatal("a scheduled profile must report a delay")
	}
	if want := 9*time.Minute + 0*time.Second; delay != want {
		t.Fatalf("delay = %s, want %s", delay, want)
	}
}

func TestDelaySettlesWhenDue(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)

	// Overdue: the next download waits for the settle delay instead of firing
	// inside a service start.
	if delay, ok := Delay(now, now.Add(-2*time.Hour), 10, SettleDelay); !ok || delay != SettleDelay {
		t.Fatalf("overdue delay = %s (ok=%v), want %s", delay, ok, SettleDelay)
	}

	// Never downloaded: treated as due now.
	if delay, ok := Delay(now, time.Time{}, 10, SettleDelay); !ok || delay != SettleDelay {
		t.Fatalf("unscheduled last update delay = %s (ok=%v), want %s", delay, ok, SettleDelay)
	}

	// Desktop floor: same rule, longer wait.
	if delay, ok := Delay(now, now.Add(-2*time.Hour), 10, DesktopSettleDelay); !ok || delay != DesktopSettleDelay {
		t.Fatalf("desktop overdue delay = %s (ok=%v), want %s", delay, ok, DesktopSettleDelay)
	}
}

func TestDelayNeverBelowSettle(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)

	// Due in one second but the floor is five: the floor wins.
	delay, ok := Delay(now, now.Add(-10*time.Minute+time.Second), 10, SettleDelay)
	if !ok || delay != SettleDelay {
		t.Fatalf("delay = %s (ok=%v), want %s", delay, ok, SettleDelay)
	}
}

func TestDelayWithoutSchedule(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)

	for _, interval := range []int{0, -1} {
		if delay, ok := Delay(now, now, interval, SettleDelay); ok || delay != 0 {
			t.Fatalf("interval %d: delay = %s (ok=%v), want no schedule", interval, delay, ok)
		}
	}
}

func TestDelayMilliseconds(t *testing.T) {
	now := time.Now()
	last := now.Add(-time.Minute)
	nowMs := now.UnixMilli()

	if got := DelayMilliseconds(nowMs, last.UnixMilli(), 10); got != int64((9 * time.Minute).Milliseconds()) {
		t.Fatalf("DelayMilliseconds = %d ms, want %d", got, (9 * time.Minute).Milliseconds())
	}
	if got := DelayMilliseconds(nowMs, 0, 30); got != SettleDelay.Milliseconds() {
		t.Fatalf("DelayMilliseconds for a never downloaded profile = %d ms, want %d", got, SettleDelay.Milliseconds())
	}
	if got := DelayMilliseconds(nowMs, last.UnixMilli(), 0); got != -1 {
		t.Fatalf("DelayMilliseconds without a schedule = %d, want -1", got)
	}
}

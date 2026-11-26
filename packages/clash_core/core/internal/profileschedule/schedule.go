// Package profileschedule owns the rule for when a profile is refreshed again.
//
// The desktop daemon, the Android VPN service, the iOS Packet Tunnel and the
// Dart app all keep a timer of their own (each process owns its run loop), but
// they must agree on when that timer fires. Keeping the arithmetic here is what
// makes a background refresh look the same on every surface.
package profileschedule

import "time"

// SettleDelay is the shortest wait before a refresh that is already due.
//
// It keeps a service start from being followed by a download in the same
// instant. Mobile services only need a few seconds: the process lives exactly
// as long as the tunnel, so the refresh is cheap to do soon after starting.
const SettleDelay = 5 * time.Second

// DesktopSettleDelay is the floor the desktop daemon and the Dart app use:
// starting the app must not immediately download the subscription again, and
// ten minutes is long enough for the app to have just written config.yaml.
const DesktopSettleDelay = 10 * time.Minute

// Delay returns how long to wait before the next refresh of a profile that was
// downloaded at lastUpdate and refreshes every intervalMinutes minutes.
// A zero lastUpdate means the profile was never downloaded, so it is due now.
// The result is never shorter than settle; a non-positive settle falls back to
// SettleDelay. ok is false when the profile has no schedule.
func Delay(now time.Time, lastUpdate time.Time, intervalMinutes int, settle time.Duration) (time.Duration, bool) {
	if intervalMinutes <= 0 {
		return 0, false
	}
	if settle <= 0 {
		settle = SettleDelay
	}

	due := now
	if !lastUpdate.IsZero() {
		due = lastUpdate.Add(time.Duration(intervalMinutes) * time.Minute)
	}
	if !due.After(now) {
		return settle, true
	}

	delay := due.Sub(now)
	if delay < settle {
		return settle, true
	}
	return delay, true
}

// DelayMilliseconds is Delay for the platform bridges, which measure time in
// milliseconds since the Unix epoch. It returns -1 when the profile has no
// schedule.
func DelayMilliseconds(nowMs int64, lastUpdateMs int64, intervalMinutes int64) int64 {
	now := time.UnixMilli(nowMs)
	var last time.Time
	if lastUpdateMs > 0 {
		last = time.UnixMilli(lastUpdateMs)
	}
	delay, ok := Delay(now, last, int(intervalMinutes), SettleDelay)
	if !ok {
		return -1
	}
	return delay.Milliseconds()
}

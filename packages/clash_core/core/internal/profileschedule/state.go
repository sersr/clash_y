package profileschedule

// This file owns the on-disk schedule the mobile runtimes share with the core.
//
// The desktop daemon keeps the profile in its own state file, because the app
// hands it over through the control API. The mobile tunnel processes get it from
// the app over the same socket, so the schedule has to live next to config.yaml
// where both processes can read it without a platform-specific store.

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// FileName is the schedule file written inside the config directory.
const FileName = "profile-schedule.json"

// Schedule is the profile a tunnel process refreshes on its own.
type Schedule struct {
	URL string `json:"url"`
	// Script is the profile's JavaScript transform, empty when unused.
	Script string `json:"script,omitempty"`
	// IntervalMinutes disables the schedule when zero or negative.
	IntervalMinutes int `json:"interval"`
	// LastUpdateMs is the last download attempt, in milliseconds since the
	// Unix epoch; zero means the profile was never downloaded.
	LastUpdateMs int64 `json:"lastUpdate"`
}

// Scheduled reports whether the profile has a refresh interval.
func (s *Schedule) Scheduled() bool {
	return s != nil && s.URL != "" && s.IntervalMinutes > 0
}

// LastUpdate returns the last download attempt as a time; the zero value means
// it never happened.
func (s *Schedule) LastUpdate() time.Time {
	if s == nil || s.LastUpdateMs <= 0 {
		return time.Time{}
	}
	return time.UnixMilli(s.LastUpdateMs)
}

// Delay reports how long to wait before the next refresh. It returns false when
// the profile has no schedule.
func (s *Schedule) Delay(now time.Time, settle time.Duration) (time.Duration, bool) {
	if !s.Scheduled() {
		return 0, false
	}
	return Delay(now, s.LastUpdate(), s.IntervalMinutes, settle)
}

// Load reads the schedule of dir. A missing file is not an error: it returns
// (nil, nil) so callers can start with no schedule.
func Load(dir string) (*Schedule, error) {
	if dir == "" {
		return nil, errors.New("config dir is empty")
	}
	payload, err := os.ReadFile(filepath.Join(dir, FileName))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil
		}
		return nil, fmt.Errorf("read profile schedule: %w", err)
	}

	var schedule Schedule
	if err := json.Unmarshal(payload, &schedule); err != nil {
		return nil, fmt.Errorf("parse profile schedule: %w", err)
	}
	return &schedule, nil
}

// Save writes the schedule of dir, replacing the previous file atomically.
// A nil schedule removes the file.
func Save(dir string, schedule *Schedule) error {
	if dir == "" {
		return errors.New("config dir is empty")
	}
	path := filepath.Join(dir, FileName)
	if schedule == nil {
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove profile schedule: %w", err)
		}
		return nil
	}

	payload, err := json.Marshal(schedule)
	if err != nil {
		return fmt.Errorf("encode profile schedule: %w", err)
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, payload, 0o600); err != nil {
		return fmt.Errorf("write profile schedule: %w", err)
	}
	if err := os.Rename(temporary, path); err != nil {
		_ = os.Remove(temporary)
		return fmt.Errorf("commit profile schedule: %w", err)
	}
	return nil
}

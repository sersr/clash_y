package profilescheduler

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"mihomo-so/internal/profileschedule"
)

const appConfig = `proxies:
    - name: app
      type: ss
mixed-port: 7890
`

const subscriptionConfig = `proxies:
    - name: fresh
      type: ss
`

func newDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "config.yaml"), []byte(appConfig), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	return dir
}

func feed(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(subscriptionConfig))
	}))
}

type applyCounter struct {
	mu    sync.Mutex
	calls int
}

func (a *applyCounter) apply() error {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.calls++
	return nil
}

func (a *applyCounter) count() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.calls
}

func TestDueScheduleRefreshesAndApplies(t *testing.T) {
	dir := newDir(t)
	server := feed(t)
	defer server.Close()

	if err := profileschedule.Save(dir, &profileschedule.Schedule{
		URL:             server.URL,
		IntervalMinutes: 1,
		LastUpdateMs:    time.Now().Add(-2 * time.Minute).UnixMilli(),
	}); err != nil {
		t.Fatalf("save schedule: %v", err)
	}

	counter := &applyCounter{}
	scheduler := New(dir, t.Logf, counter.apply)
	scheduler.Settle = 20 * time.Millisecond
	scheduler.Start()
	defer scheduler.Stop()

	waitFor(t, func() bool { return counter.count() == 1 })

	configured, err := os.ReadFile(filepath.Join(dir, "config.yaml"))
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if !bytes.Contains(configured, []byte("name: fresh")) || !bytes.Contains(configured, []byte("mixed-port: 7890")) {
		t.Fatalf("config was not refreshed with the app-owned keys:\n%s", configured)
	}

	schedule, err := profileschedule.Load(dir)
	if err != nil {
		t.Fatalf("load schedule: %v", err)
	}
	if age := time.Since(schedule.LastUpdate()); age > time.Minute {
		t.Fatalf("refresh did not record the attempt, last update %s ago", age)
	}
}

func TestFailedRefreshStillCountsAsAttempt(t *testing.T) {
	dir := newDir(t)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	if err := profileschedule.Save(dir, &profileschedule.Schedule{
		URL:             server.URL,
		IntervalMinutes: 1,
	}); err != nil {
		t.Fatalf("save schedule: %v", err)
	}

	counter := &applyCounter{}
	scheduler := New(dir, t.Logf, counter.apply)
	scheduler.Settle = 20 * time.Millisecond
	scheduler.Start()
	defer scheduler.Stop()

	waitFor(t, func() bool {
		schedule, err := profileschedule.Load(dir)
		return err == nil && schedule.LastUpdateMs > 0
	})
	if counter.count() != 0 {
		t.Fatalf("a failed download must not apply a config, applied %d times", counter.count())
	}
}

func TestWakePicksUpANewSchedule(t *testing.T) {
	dir := newDir(t)
	server := feed(t)
	defer server.Close()

	counter := &applyCounter{}
	scheduler := New(dir, t.Logf, counter.apply)
	scheduler.Settle = 20 * time.Millisecond
	scheduler.Start()
	defer scheduler.Stop()

	// No schedule yet: the loop must be idle, not spinning or exiting.
	time.Sleep(50 * time.Millisecond)
	if counter.count() != 0 {
		t.Fatalf("refreshed without a schedule")
	}

	if err := profileschedule.Save(dir, &profileschedule.Schedule{
		URL:             server.URL,
		IntervalMinutes: 1,
	}); err != nil {
		t.Fatalf("save schedule: %v", err)
	}
	scheduler.Wake()
	waitFor(t, func() bool { return counter.count() == 1 })
}

func TestStopEndsTheLoop(t *testing.T) {
	dir := newDir(t)
	scheduler := New(dir, t.Logf, nil)
	scheduler.Start()

	done := make(chan struct{})
	go func() {
		scheduler.Stop()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Stop did not return")
	}
	// Stop must stay safe after the loop is gone.
	scheduler.Stop()
}

func waitFor(t *testing.T, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("condition was not met in time")
}

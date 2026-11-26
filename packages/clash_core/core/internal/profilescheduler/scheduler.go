// Package profilescheduler refreshes a tunnel's profile on its own timer.
//
// Go owns the timer because it runs inside the tunnel process: Android's `:vpn`
// process and the iOS Packet Tunnel extension both outlive the app, so a
// background refresh needs no platform hook, no second copy of the delay rule
// and no native HTTP client. The platform only starts and stops the core.
package profilescheduler

import (
	"sync"
	"time"

	"mihomo-so/internal/profilerefresh"
	"mihomo-so/internal/profileschedule"
)

// Scheduler watches the schedule of one config directory.
type Scheduler struct {
	dir   string
	logf  func(format string, args ...any)
	apply func() error

	// Settle is the shortest wait before an already due refresh; tests lower
	// it, production keeps profileschedule.SettleDelay.
	Settle time.Duration

	wake chan struct{}
	stop chan struct{}
	done chan struct{}
	once sync.Once
}

// New creates a scheduler for dir. apply is called after a successful refresh,
// so the running core picks up the new config without a platform restart.
// logf may be nil.
func New(dir string, logf func(format string, args ...any), apply func() error) *Scheduler {
	if logf == nil {
		logf = func(string, ...any) {}
	}
	return &Scheduler{
		dir:    dir,
		logf:   logf,
		apply:  apply,
		Settle: profileschedule.SettleDelay,
		wake:   make(chan struct{}, 1),
		stop:   make(chan struct{}),
		done:   make(chan struct{}),
	}
}

// Start runs the loop in the background.
func (s *Scheduler) Start() {
	go s.loop()
}

// Stop ends the loop and waits for it. Safe to call more than once.
func (s *Scheduler) Stop() {
	s.once.Do(func() { close(s.stop) })
	<-s.done
}

// Wake makes the loop re-read the schedule, e.g. after the app switched
// profiles through the control API. It never blocks.
func (s *Scheduler) Wake() {
	select {
	case s.wake <- struct{}{}:
	default:
	}
}

func (s *Scheduler) loop() {
	defer close(s.done)

	for {
		schedule, err := profileschedule.Load(s.dir)
		if err != nil {
			s.logf("read profile schedule: %v", err)
		}

		if !schedule.Scheduled() {
			select {
			case <-s.stop:
				return
			case <-s.wake:
				continue
			}
		}

		delay, ok := schedule.Delay(time.Now(), s.Settle)
		if !ok {
			continue
		}

		timer := time.NewTimer(delay)
		select {
		case <-s.stop:
			timer.Stop()
			return
		case <-s.wake:
			timer.Stop()
			continue
		case <-timer.C:
			s.refresh()
		}
	}
}

// refresh runs once, records the attempt in the schedule and applies the new
// config. A failed download still counts as an attempt, so the next one waits a
// full interval instead of retrying in a tight loop.
func (s *Scheduler) refresh() {
	schedule, err := profileschedule.Load(s.dir)
	if err != nil || !schedule.Scheduled() {
		return
	}

	refreshErr := profilerefresh.RefreshFile(s.dir, schedule.URL, schedule.Script)
	if refreshErr != nil {
		s.logf("scheduled profile refresh failed: %v", refreshErr)
	}

	schedule.LastUpdateMs = time.Now().UnixMilli()
	if err := profileschedule.Save(s.dir, schedule); err != nil {
		s.logf("record profile refresh: %v", err)
	}

	if refreshErr != nil {
		return
	}
	if err := s.apply(); err != nil {
		s.logf("apply refreshed config: %v", err)
	}
}

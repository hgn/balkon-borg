// Storm warning (U9.3): a fast, sustained pressure drop is the classic sign of an
// approaching low front, worth a spoken warning before it arrives.
//
// Pure logic, same shape as the ADS-B low-pass detector in adsb.go: a threshold check
// plus a cooldown so the same weather event does not refire every time it is checked.
package main

import (
	"fmt"
	"time"
)

// StormDetector decides whether the environment history shows a sustained pressure
// drop worth a warning.
//
// The failure mode this exists to avoid: the Pi is off most of the time, so the
// history has gaps, and a boot after two days off puts "now" right next to a sample
// from Tuesday in the ring. Read naively that looks like a catastrophic pressure
// drop. MaxGap draws the line between "continuous weather data" and "the unit was
// simply off"; a gap wider than that breaks the lookback instead of feeding it.
type StormDetector struct {
	DropHPaPerHour float64
	WindowHours    float64
	MaxGap         time.Duration
	Cooldown       time.Duration

	lastFired time.Time
	now       func() time.Time
}

func NewStormDetector(dropHPaPerHour, windowHours float64, maxGap, cooldown time.Duration,
	now func() time.Time) *StormDetector {
	if now == nil {
		now = time.Now
	}
	return &StormDetector{
		DropHPaPerHour: dropHPaPerHour,
		WindowHours:    windowHours,
		MaxGap:         maxGap,
		Cooldown:       cooldown,
		now:            now,
	}
}

// Check evaluates the pressure history, newest first (EnvHistory.Samples' order), and
// reports whether a storm warning is due right now. On a hit it records the time, so
// calling it is itself the "I have reported this" mark, exactly like LowPass.Check.
func (s *StormDetector) Check(history []EnvSample) (fire bool, dropHPa float64) {
	drop, ok := s.sustainedDrop(history)
	if !ok {
		return false, 0
	}
	now := s.now()
	if !s.lastFired.IsZero() && now.Sub(s.lastFired) < s.Cooldown {
		return false, 0
	}
	s.lastFired = now
	return true, drop
}

// sustainedDrop walks the history backwards from the newest sample, accumulating real
// elapsed time until it covers the configured window, and reports the drop over that
// span. It refuses to look past a gap wider than MaxGap: a history that does not
// continuously cover the window is not evidence of anything, sustained or not.
func (s *StormDetector) sustainedDrop(history []EnvSample) (dropHPa float64, ok bool) {
	if len(history) < 2 {
		return 0, false
	}
	latest, err := time.Parse(time.RFC3339, history[0].TS)
	if err != nil {
		return 0, false
	}
	// The newest sample has to be recent as well. A dead ESP leaves a history that
	// still ends in a real drop, and hours later that is weather from this morning,
	// not a warning worth waking somebody for.
	if s.now().Sub(latest) > s.MaxGap {
		return 0, false
	}
	window := time.Duration(s.WindowHours * float64(time.Hour))

	prev := latest
	for i := 1; i < len(history); i++ {
		ts, err := time.Parse(time.RFC3339, history[i].TS)
		if err != nil {
			return 0, false
		}
		if prev.Sub(ts) > s.MaxGap {
			return 0, false // the unit was off, not the weather changing
		}
		prev = ts

		elapsed := latest.Sub(ts)
		if elapsed < window {
			continue
		}
		hours := elapsed.Hours()
		if hours <= 0 {
			return 0, false
		}
		drop := history[i].P - history[0].P
		if drop/hours < s.DropHPaPerHour {
			return 0, false
		}
		return drop, true
	}
	return 0, false // history does not reach back far enough yet
}

// StormEventText is the German line the phone notification shows.
func StormEventText(dropHPa, windowHours float64) string {
	return fmt.Sprintf(
		"Sturmwarnung: Luftdruck fällt schnell (%.1f hPa in %.0f h) – Kissen reinholen.",
		dropHPa, windowHours)
}

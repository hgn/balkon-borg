package main

import (
	"testing"
	"time"
)

// movableClock returns a func() time.Time reading a *time.Time, so a test can move it
// forward between calls the way storm_test.go's cooldown test does.
func movableClock(t *time.Time) func() time.Time {
	return func() time.Time { return *t }
}

func newTestLadder(now *time.Time) *SentryLadder {
	return NewSentryLadder(movableClock(now),
		60*time.Second, // exit delay
		15*time.Second, // person window
		30*time.Second, // entry grace
		60*time.Second, // alarm cooldown
		2*time.Minute,  // armed reminder pulse
	)
}

func boolPtr(v bool) *bool { return &v }

func TestSentryStartsOff(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	if s.State() != Off {
		t.Errorf("expected off, got %q", s.State())
	}
}

// --- arming --------------------------------------------------------------------

func TestArmMovesOffToArmingAndPins(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)

	eff := s.Arm()
	if eff.Submode != SentryArming {
		t.Errorf("expected submode %q, got %q", SentryArming, eff.Submode)
	}
	if eff.Pin == nil || !*eff.Pin {
		t.Error("arming must pin the camera to Frigate")
	}
	if s.State() != SentryArming {
		t.Errorf("expected state %q, got %q", SentryArming, s.State())
	}
}

func TestArmIsANoOpUnlessOff(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()

	for _, state := range []string{SentryArming, SentryArmed, SentryGrace, SentryAlarm} {
		s.state = state // reach into the state directly, this is a whitebox test
		eff := s.Arm()
		if eff != (SentryEffect{}) {
			t.Errorf("arming from %q should be a no-op, got %+v", state, eff)
		}
		if s.State() != state {
			t.Errorf("arming from %q must not move the state, got %q", state, s.State())
		}
	}
}

func TestSceneClearDuringArmingGoesLiveImmediately(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()

	// Well before the exit delay: the "clear once" half of the gate must win on its
	// own, not wait for the fallback too.
	now = now.Add(5 * time.Second)
	eff := s.SceneClear()
	if eff.Submode != SentryArmed {
		t.Errorf("expected armed, got %+v", eff)
	}
	if eff.Pin != nil {
		t.Error("the pin does not change on arming -> armed, it is already pinned")
	}
}

func TestArmingFallsBackToArmedAfterExitDelay(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()

	// One second short: must still be arming, nobody ever reported a clear scene.
	now = now.Add(59 * time.Second)
	if eff := s.Tick(); eff.Submode != "" {
		t.Errorf("expected no transition yet, got %+v", eff)
	}
	if s.State() != SentryArming {
		t.Fatalf("expected still arming, got %q", s.State())
	}

	// Exactly at the deadline: the boundary counts as elapsed.
	now = now.Add(1 * time.Second)
	eff := s.Tick()
	if eff.Submode != SentryArmed {
		t.Errorf("expected the exit-delay fallback to fire, got %+v", eff)
	}
}

// --- presence / person confirmation --------------------------------------------

func TestPresenceWithoutPersonFallsBackToArmedWithinTheWindow(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear() // -> armed

	if eff := s.PresenceSeen(); eff != (SentryEffect{}) {
		t.Errorf("presence alone must not change the submode, got %+v", eff)
	}
	if s.State() != SentryArmed {
		t.Fatalf("expected still armed while watching, got %q", s.State())
	}

	// The window lapses with no Frigate confirmation.
	now = now.Add(15 * time.Second)
	if eff := s.Tick(); eff != (SentryEffect{}) {
		t.Errorf("the window lapsing must not itself produce a visible effect, got %+v", eff)
	}
	if s.State() != SentryArmed {
		t.Errorf("must fall back to plain armed watching, got %q", s.State())
	}

	// A person detection arriving late (window already lapsed) must not retroactively
	// escalate: it is exactly the "presence without a person" case, closed for good.
	if eff := s.PersonDetected(); eff != (SentryEffect{}) {
		t.Errorf("a late confirmation must be ignored, got %+v", eff)
	}
	if s.State() != SentryArmed {
		t.Errorf("a late confirmation must not move the state, got %q", s.State())
	}
}

func TestPersonWithoutPresenceIsIgnored(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear() // -> armed, but no PresenceSeen was ever called

	eff := s.PersonDetected()
	if eff != (SentryEffect{}) {
		t.Errorf("a Frigate detection with no radar wake behind it must do nothing, got %+v", eff)
	}
	if s.State() != SentryArmed {
		t.Errorf("expected to stay armed, got %q", s.State())
	}
}

func TestPersonDetectedOutsideArmedIsIgnored(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)

	// Off: nothing to confirm.
	if eff := s.PersonDetected(); eff != (SentryEffect{}) {
		t.Errorf("expected no effect while off, got %+v", eff)
	}

	// Arming: a person detection while you are still walking out must not trip the
	// ladder on yourself.
	s.Arm()
	if eff := s.PersonDetected(); eff != (SentryEffect{}) {
		t.Errorf("expected no effect while arming, got %+v", eff)
	}
	if s.State() != SentryArming {
		t.Errorf("must not have moved off arming, got %q", s.State())
	}
}

func TestPresenceThenPersonWithinTheWindowEntersGrace(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear() // -> armed

	s.PresenceSeen()
	now = now.Add(5 * time.Second) // well inside the 15s window
	eff := s.PersonDetected()
	if eff.Submode != SentryGrace {
		t.Errorf("expected grace, got %+v", eff)
	}
	if eff.Flash || eff.Beep || eff.Record || eff.EventText != "" {
		t.Errorf("entering grace must not fire the effector yet, got %+v", eff)
	}
	if s.State() != SentryGrace {
		t.Errorf("expected state grace, got %q", s.State())
	}
}

// --- entry grace and the alarm ---------------------------------------------------

func TestDisarmDuringGraceStopsEverything(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear()
	s.PresenceSeen()
	s.PersonDetected() // -> grace

	now = now.Add(10 * time.Second) // inside the 30s grace window
	eff := s.Disarm()
	if eff.Submode != Off {
		t.Errorf("expected off, got %+v", eff)
	}
	if eff.Pin == nil || *eff.Pin {
		t.Error("disarm must release the camera pin")
	}

	// Letting the original grace deadline pass must not fire the alarm behind the
	// disarm: the deadline belongs to a sequence that no longer exists.
	now = now.Add(25 * time.Second) // past the original 30s grace deadline
	if eff := s.Tick(); eff != (SentryEffect{}) {
		t.Errorf("a stale deadline from before disarm must not fire, got %+v", eff)
	}
	if s.State() != Off {
		t.Errorf("expected to stay off, got %q", s.State())
	}
}

func TestGraceLapsingFiresTheAlarm(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear()
	s.PresenceSeen()
	s.PersonDetected() // -> grace

	now = now.Add(30 * time.Second) // exactly the entry-grace deadline
	eff := s.Tick()
	if eff.Submode != SentryAlarm {
		t.Fatalf("expected alarm, got %+v", eff)
	}
	if !eff.Flash || !eff.Beep || !eff.Record {
		t.Errorf("the alarm transition must fire the whole effector, got %+v", eff)
	}
	if eff.EventText == "" {
		t.Error("expected event text for the phone ring")
	}
	if s.State() != SentryAlarm {
		t.Errorf("expected state alarm, got %q", s.State())
	}
}

// --- the retrigger rule: this is the one the task cares about most -------------

func TestAlarmDoesNotRefireWhileThePersonLingers(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear()
	s.PresenceSeen()
	s.PersonDetected()
	now = now.Add(30 * time.Second)
	first := s.Tick()
	if first.Submode != SentryAlarm {
		t.Fatalf("expected the first alarm to fire, got %+v", first)
	}

	// The person is still standing there: Frigate keeps sending detections, the
	// radar keeps reporting presence. None of it may fire a second alarm while the
	// cooldown is running.
	for i := 0; i < 5; i++ {
		now = now.Add(time.Second)
		if eff := s.PersonDetected(); eff != (SentryEffect{}) {
			t.Fatalf("a lingering person must not re-fire during cooldown, got %+v", eff)
		}
		if eff := s.PresenceSeen(); eff != (SentryEffect{}) {
			t.Fatalf("presence during cooldown must not do anything either, got %+v", eff)
		}
		if s.State() != SentryAlarm {
			t.Fatalf("must stay in alarm/cooldown, got %q", s.State())
		}
	}
}

func TestRetriggerSceneClearsEarly(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear()
	s.PresenceSeen()
	s.PersonDetected()
	now = now.Add(30 * time.Second)
	s.Tick() // -> alarm

	// The person leaves well before the 60s cooldown fallback.
	now = now.Add(5 * time.Second)
	eff := s.SceneClear()
	if eff.Submode != SentryArmed {
		t.Fatalf("expected the scene-clear to return to armed early, got %+v", eff)
	}
	if s.State() != SentryArmed {
		t.Errorf("expected armed, got %q", s.State())
	}

	// It must be a genuinely fresh watch: a new presence+person cycle can fire again.
	s.PresenceSeen()
	eff = s.PersonDetected()
	if eff.Submode != SentryGrace {
		t.Errorf("expected the ladder to be able to retrigger after a clean return to armed, got %+v", eff)
	}
}

func TestRetriggerSceneNeverClearsFallsBackOnCooldown(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear()
	s.PresenceSeen()
	s.PersonDetected()
	now = now.Add(30 * time.Second)
	s.Tick() // -> alarm

	// The radar never reports a clear scene again (the person just stands there).
	now = now.Add(59 * time.Second)
	if eff := s.Tick(); eff != (SentryEffect{}) {
		t.Errorf("expected still cooling down one second before the fallback, got %+v", eff)
	}
	now = now.Add(1 * time.Second)
	eff := s.Tick()
	if eff.Submode != SentryArmed {
		t.Fatalf("expected the cooldown fallback to return to armed, got %+v", eff)
	}
	if eff.Flash || eff.Beep || eff.Record || eff.EventText != "" {
		t.Errorf("the cooldown fallback must not re-fire the effector, got %+v", eff)
	}
}

// --- disarm from every rung of the ladder ---------------------------------------

func TestDisarmFromEveryStateReturnsOffAndUnpins(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)

	build := func() (*SentryLadder, *time.Time) {
		n := time.Unix(1_800_000_000, 0)
		return newTestLadder(&n), &n
	}
	_ = now

	steps := map[string]func(s *SentryLadder, now *time.Time){
		SentryArming: func(s *SentryLadder, now *time.Time) { s.Arm() },
		SentryArmed: func(s *SentryLadder, now *time.Time) {
			s.Arm()
			s.SceneClear()
		},
		SentryGrace: func(s *SentryLadder, now *time.Time) {
			s.Arm()
			s.SceneClear()
			s.PresenceSeen()
			s.PersonDetected()
		},
		SentryAlarm: func(s *SentryLadder, now *time.Time) {
			s.Arm()
			s.SceneClear()
			s.PresenceSeen()
			s.PersonDetected()
			*now = now.Add(30 * time.Second)
			s.Tick()
		},
	}

	for state, setup := range steps {
		s, n := build()
		setup(s, n)
		if s.State() != state {
			t.Fatalf("setup for %q left the ladder in %q", state, s.State())
		}
		eff := s.Disarm()
		if eff.Submode != Off {
			t.Errorf("disarm from %q: expected off, got %+v", state, eff)
		}
		if eff.Pin == nil || *eff.Pin {
			t.Errorf("disarm from %q must release the pin", state)
		}
		if s.State() != Off {
			t.Errorf("disarm from %q: expected state off, got %q", state, s.State())
		}
		// Ticking after disarm must be inert: no deadline should still be running.
		*n = n.Add(time.Hour)
		if tickEff := s.Tick(); tickEff != (SentryEffect{}) {
			t.Errorf("disarm from %q left a live deadline behind: %+v", state, tickEff)
		}
	}
}

func TestDisarmWhileAlreadyOffIsANoOp(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	if eff := s.Disarm(); eff != (SentryEffect{}) {
		t.Errorf("disarming an already-off ladder should do nothing, got %+v", eff)
	}
}

// --- re-arming after a full cycle -------------------------------------------------

func TestReArmingAfterAFullCycleStartsClean(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	s.Arm()
	s.SceneClear()
	s.PresenceSeen()
	s.PersonDetected()
	now = now.Add(30 * time.Second)
	s.Tick() // -> alarm
	s.Disarm()

	if s.State() != Off {
		t.Fatalf("expected off after disarm, got %q", s.State())
	}

	// Advancing the clock far past every old deadline must not spuriously fire
	// anything from the previous cycle once re-armed.
	now = now.Add(24 * time.Hour)
	eff := s.Arm()
	if eff.Submode != SentryArming {
		t.Fatalf("expected a clean arming sequence, got %+v", eff)
	}
	if tickEff := s.Tick(); tickEff != (SentryEffect{}) {
		t.Errorf("a fresh arming must not immediately fire anything, got %+v", tickEff)
	}
	if s.State() != SentryArming {
		t.Errorf("expected still arming, got %q", s.State())
	}
}

// --- clock gate -------------------------------------------------------------------

func TestTickIsInertWithNoDeadlinePending(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	s := newTestLadder(&now)
	// Off: no deadline at all.
	if eff := s.Tick(); eff != (SentryEffect{}) {
		t.Errorf("expected no effect while off, got %+v", eff)
	}

	s.Arm()
	s.SceneClear() // -> armed, deadline cleared again
	now = now.Add(365 * 24 * time.Hour)
	// Armed with nothing pending never escalates on its own. The only thing a tick
	// may produce here is the armed reminder, which is exactly what it does produce
	// after a year of waiting.
	eff := s.Tick()
	if eff.Submode != "" || eff.Flash || eff.Beep || eff.Record {
		t.Errorf("armed with no pending window must not escalate, got %+v", eff)
	}
	if !eff.Pulse {
		t.Error("expected the armed reminder to be the one thing a quiet tick emits")
	}
	if s.State() != SentryArmed {
		t.Errorf("expected still armed, got %q", s.State())
	}
}

// The armed reminder (user call 2026-07-18): an armed system nobody remembers arming
// is one that gets disabled in anger the first time it fires at the wrong moment.
func TestArmedPulseRemindsPeriodically(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	l := NewSentryLadder(func() time.Time { return now },
		time.Minute, 15*time.Second, 30*time.Second, time.Minute, 2*time.Minute)

	l.Arm()
	l.SceneClear() // arming -> armed

	if eff := l.Tick(); eff.Pulse {
		t.Fatal("the pulse should wait an interval, arriving armed is visible enough")
	}

	now = now.Add(2 * time.Minute)
	if eff := l.Tick(); !eff.Pulse {
		t.Fatal("expected the armed reminder after the interval")
	}
	if eff := l.Tick(); eff.Pulse {
		t.Error("one reminder per interval, not one per tick")
	}

	now = now.Add(2 * time.Minute)
	if eff := l.Tick(); !eff.Pulse {
		t.Error("expected the next reminder an interval later")
	}
}

func TestNothingPulsesWhileDisarmed(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	l := NewSentryLadder(func() time.Time { return now },
		time.Minute, 15*time.Second, 30*time.Second, time.Minute, time.Second)

	for i := 0; i < 5; i++ {
		now = now.Add(time.Second)
		if eff := l.Tick(); eff.Pulse {
			t.Fatal("a disarmed unit has nothing to remind anybody of")
		}
	}
}

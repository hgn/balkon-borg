package main

import (
	"testing"
	"time"
)

// fixedClock keeps timestamps out of the assertions; where "since" matters, the test
// advances it explicitly.
func fixedClock(t time.Time) func() time.Time { return func() time.Time { return t } }

func TestModesStartOff(t *testing.T) {
	m := NewModes(fixedClock(time.Unix(0, 0)))
	for _, mode := range AllModes {
		if !m.Get(mode).IsOff() {
			t.Errorf("%s should start off, got %q", mode, m.Get(mode).Submode)
		}
	}
}

func TestApplyReportsOnlyRealChanges(t *testing.T) {
	m := NewModes(fixedClock(time.Unix(0, 0)))

	changed, err := m.Apply(Lumen, "cozy", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(changed) != 1 || changed[0] != Lumen {
		t.Fatalf("expected lumen to change, got %v", changed)
	}

	// The same command again is not a change: clients re-send state, and a republish
	// would fire the app's confirmation haptic for nothing.
	changed, err = m.Apply(Lumen, "cozy", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(changed) != 0 {
		t.Fatalf("re-applying the same submode should change nothing, got %v", changed)
	}
}

func TestApplyRejectsAnUnknownSubmode(t *testing.T) {
	m := NewModes(fixedClock(time.Unix(0, 0)))
	if _, err := m.Apply(Lumen, "hyperdrive", ""); err == nil {
		t.Fatal("expected an unknown submode to be refused")
	}
	if !m.Get(Lumen).IsOff() {
		t.Error("a refused command must not change state")
	}
}

// The single-RTL-SDR rule, which is the reason this state machine exists at all.
func TestStartingCommsStopsSigint(t *testing.T) {
	m := NewModes(fixedClock(time.Unix(0, 0)))
	if _, err := m.Apply(Sigint, "adsb", ""); err != nil {
		t.Fatal(err)
	}

	changed, err := m.Apply(Comms, "fm", "bayern3")
	if err != nil {
		t.Fatal(err)
	}
	if len(changed) != 2 {
		t.Fatalf("expected both modes to change, got %v", changed)
	}
	if !m.Get(Sigint).IsOff() {
		t.Error("sigint should have been displaced")
	}
	if got := m.Get(Comms); got.Submode != "fm" || got.Chan != "bayern3" {
		t.Errorf("comms not applied: %+v", got)
	}
}

func TestStartingSigintStopsComms(t *testing.T) {
	m := NewModes(fixedClock(time.Unix(0, 0)))
	if _, err := m.Apply(Comms, "dab", ""); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Apply(Sigint, "aprs", ""); err != nil {
		t.Fatal(err)
	}
	if !m.Get(Comms).IsOff() {
		t.Error("comms should have been displaced")
	}
}

func TestTurningARadioModeOffDisplacesNothing(t *testing.T) {
	m := NewModes(fixedClock(time.Unix(0, 0)))
	if _, err := m.Apply(Sigint, "adsb", ""); err != nil {
		t.Fatal(err)
	}

	changed, err := m.Apply(Comms, Off, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(changed) != 0 {
		t.Fatalf("switching an already-off mode off changes nothing, got %v", changed)
	}
	if m.Get(Sigint).IsOff() {
		t.Error("sigint must keep running when comms is switched off")
	}
}

func TestLumenAndSentryDoNotCompeteForTheTuner(t *testing.T) {
	m := NewModes(fixedClock(time.Unix(0, 0)))
	if _, err := m.Apply(Sigint, "adsb", ""); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		mode    Mode
		submode string
	}{{Lumen, "ambient"}, {Sentry, "armed"}} {
		if _, err := m.Apply(c.mode, c.submode, ""); err != nil {
			t.Fatal(err)
		}
		if m.Get(Sigint).IsOff() {
			t.Fatalf("%s must not displace sigint", c.mode)
		}
	}
}

func TestSinceMovesOnlyWhenTheStateMoves(t *testing.T) {
	now := time.Unix(1000, 0)
	m := NewModes(func() time.Time { return now })

	if _, err := m.Apply(Lumen, "cozy", ""); err != nil {
		t.Fatal(err)
	}
	first := m.Get(Lumen).Since

	now = now.Add(time.Hour)
	if _, err := m.Apply(Lumen, "cozy", ""); err != nil {
		t.Fatal(err)
	}
	if m.Get(Lumen).Since != first {
		t.Error("since must not move when nothing changed")
	}

	if _, err := m.Apply(Lumen, "disco", ""); err != nil {
		t.Fatal(err)
	}
	if m.Get(Lumen).Since == first {
		t.Error("since must move when the submode changes")
	}
}

func TestPinIsIdempotent(t *testing.T) {
	m := NewModes(fixedClock(time.Unix(0, 0)))
	if !m.Pin(Sentry, true) {
		t.Error("first pin should report a change")
	}
	if m.Pin(Sentry, true) {
		t.Error("pinning twice should report no change")
	}
	if !m.Get(Sentry).Pinned {
		t.Error("sentry should be pinned")
	}
}

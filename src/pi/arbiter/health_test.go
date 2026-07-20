package main

import (
	"strings"
	"testing"
	"time"
)

func okProbe() (State, string)      { return StateOK, "" }
func missingProbe() (State, string) { return StateMissing, "nothing attached" }

func TestDisabledCapabilityIsNeverProbed(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	probed := false
	reg.Register("sdr", func() (State, string) { probed = true; return StateOK, "" }, false)

	reg.ProbeAll()

	if probed {
		t.Error("a disabled capability must not be probed")
	}
	if c, _ := reg.Get("sdr"); c.State != StateDisabled {
		t.Errorf("expected disabled, got %s", c.State)
	}
}

// The difference between "not wanted" and "wanted but broken" is the whole point of
// having a disabled state, so it must not colour the aggregate.
func TestDisabledDoesNotSpoilTheAggregate(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	reg.Register("camera", okProbe, true)
	reg.Register("sdr", missingProbe, false)

	if got := reg.Aggregate(); got != StateOK {
		t.Errorf("expected ok, got %s", got)
	}
}

func TestAggregateTakesTheWorstState(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	reg.Register("a", okProbe, true)
	reg.Register("b", func() (State, string) { return StateDegraded, "slow" }, true)
	reg.ProbeAll()

	if got := reg.Aggregate(); got != StateDegraded {
		t.Fatalf("expected degraded, got %s", got)
	}

	reg.Register("c", missingProbe, true)
	reg.ProbeAll()
	if got := reg.Aggregate(); got != StateMissing {
		t.Fatalf("missing outranks degraded, got %s", got)
	}
}

func TestProbeAllReportsOnlyChanges(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	state := StateOK
	reg.Register("sdr", func() (State, string) { return state, "" }, true)

	reg.ProbeAll() // settles at ok
	if changed := reg.ProbeAll(); len(changed) != 0 {
		t.Fatalf("a steady capability must not be republished, got %v", changed)
	}

	state = StateMissing
	if changed := reg.ProbeAll(); len(changed) != 1 || changed[0] != "sdr" {
		t.Fatalf("expected sdr to be reported, got %v", changed)
	}
}

// A broken probe is a degraded capability, never a crashed arbiter.
func TestAPanickingProbeDegradesInsteadOfKillingTheProcess(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	reg.Register("sdr", func() (State, string) { panic("usb went away") }, true)

	reg.ProbeAll()

	c, _ := reg.Get("sdr")
	if c.State != StateDegraded {
		t.Fatalf("expected degraded, got %s", c.State)
	}
	if !strings.Contains(c.Reason, "usb went away") {
		t.Errorf("the reason should carry the panic, got %q", c.Reason)
	}
}

func TestSinceAnswersHowLongNotWhenLastLookedAt(t *testing.T) {
	now := time.Unix(1000, 0)
	reg := NewRegistry(func() time.Time { return now })
	reg.Register("sdr", missingProbe, true)
	reg.ProbeAll()
	first, _ := reg.Get("sdr")

	now = now.Add(2 * time.Hour)
	reg.ProbeAll() // same state, later probe
	second, _ := reg.Get("sdr")

	if second.Since != first.Since {
		t.Error("since must not move while the state is unchanged")
	}
}

func TestSummaryNamesWhatIsWrong(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	reg.Register("camera", okProbe, true)
	reg.Register("sdr", missingProbe, true)
	reg.ProbeAll()

	summary := reg.Summary()
	if !strings.Contains(summary, "sdr") {
		t.Errorf("the summary should name the problem, got %q", summary)
	}
	if strings.Contains(summary, "camera") {
		t.Errorf("a healthy capability should not be listed, got %q", summary)
	}
}

func TestSummaryWhenEverythingIsFine(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	reg.Register("camera", okProbe, true)
	reg.ProbeAll()

	if got := reg.Summary(); !strings.Contains(got, "ok") {
		t.Errorf("expected an ok summary, got %q", got)
	}
}

func TestFreshnessProbe(t *testing.T) {
	now := time.Unix(10_000, 0)
	clock := func() time.Time { return now }

	never := FreshnessProbe(func() time.Time { return time.Time{} }, clock, time.Minute, "never seen")
	if state, reason := never(); state != StateMissing || reason != "never seen" {
		t.Errorf("expected missing/never seen, got %s/%s", state, reason)
	}

	fresh := FreshnessProbe(func() time.Time { return now.Add(-10 * time.Second) }, clock,
		time.Minute, "never seen")
	if state, _ := fresh(); state != StateOK {
		t.Errorf("expected ok, got %s", state)
	}

	stale := FreshnessProbe(func() time.Time { return now.Add(-10 * time.Minute) }, clock,
		time.Minute, "never seen")
	// Degraded, not missing: the source existed once, so this is silence, not absence.
	if state, _ := stale(); state != StateDegraded {
		t.Errorf("expected degraded, got %s", state)
	}
}

func TestHardwareProbesReadToolOutput(t *testing.T) {
	cases := []struct {
		name  string
		probe Probe
		want  State
	}{
		{"sdr present", SDRProbe(fakeRunner("Found 1 device(s):\n", nil)), StateOK},
		{"sdr absent", SDRProbe(fakeRunner("No supported devices found.\n", nil)), StateMissing},
		{"sdr busy", SDRProbe(fakeRunner("usb_claim_interface error -6\n", nil)), StateDegraded},
		{"sound present", SoundProbe(fakeRunner("card 0: Device [USB Audio]\n", nil)), StateOK},
		{"sound absent", SoundProbe(fakeRunner("no soundcards found\n", nil)), StateMissing},
		{"clock synced", ClockProbe(fakeRunner("yes\n", nil)), StateOK},
		{"clock unsynced", ClockProbe(fakeRunner("no\n", nil)), StateDegraded},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if state, _ := c.probe(); state != c.want {
				t.Errorf("expected %s, got %s", c.want, state)
			}
		})
	}
}

func fakeRunner(out string, err error) commandRunner {
	return func(string, ...string) (string, error) { return out, err }
}

func TestCameraProbeChecksTheNodeWithoutOpeningIt(t *testing.T) {
	present := CameraProbe(func(string) bool { return true })
	if state, _ := present(); state != StateOK {
		t.Errorf("expected ok, got %s", state)
	}
	absent := CameraProbe(func(string) bool { return false })
	if state, _ := absent(); state != StateMissing {
		t.Errorf("expected missing, got %s", state)
	}
}

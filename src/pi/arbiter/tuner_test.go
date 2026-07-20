package main

import (
	"testing"
	"time"
)

func newTestTuner() *Tuner { return NewTuner(fixedClock(time.Unix(1000, 0))) }

// The tuner is never idle: listening for aircraft costs nothing extra, so ADS-B runs
// whenever nobody else wants the stick.
func TestTheTunerStartsOnAdsb(t *testing.T) {
	if got := newTestTuner().Current().Consumer; got != ConsumerAdsb {
		t.Errorf("expected the idle default, got %q", got)
	}
}

func TestListeningDisplacesObservation(t *testing.T) {
	tuner := newTestTuner()
	running, changed, err := tuner.Request(Claim{Consumer: ConsumerListening, Band: "fm"})
	if err != nil {
		t.Fatal(err)
	}
	if !changed || running.Consumer != ConsumerListening {
		t.Fatalf("the user should win, got %+v changed=%v", running, changed)
	}
}

func TestObservationDoesNotInterruptTheUser(t *testing.T) {
	tuner := newTestTuner()
	tuner.Request(Claim{Consumer: ConsumerListening, Band: "fm"})

	running, changed, err := tuner.Request(Claim{Consumer: ConsumerIsm})
	if err != nil {
		t.Fatal(err)
	}
	if changed || running.Consumer != ConsumerListening {
		t.Fatalf("listening should keep the tuner, got %+v", running)
	}
	// The losing claim is remembered, not dropped.
	if waiting := tuner.Waiting(); len(waiting) != 1 || waiting[0] != ConsumerIsm {
		t.Errorf("expected ism to be queued, got %v", waiting)
	}
}

// The behaviour that makes the queue worth having: after listening ends, the tuner goes
// back to what was interrupted, not to the idle default.
func TestReleasingHandsBackToTheHighestWaitingClaim(t *testing.T) {
	tuner := newTestTuner()
	tuner.Request(Claim{Consumer: ConsumerIsm})
	tuner.Request(Claim{Consumer: ConsumerRadiosonde}) // outranks ism, takes over
	tuner.Request(Claim{Consumer: ConsumerListening})  // user outranks both

	running, changed := tuner.Release(ConsumerListening)
	if !changed || running.Consumer != ConsumerRadiosonde {
		t.Fatalf("the sonde should resume, got %+v", running)
	}

	running, _ = tuner.Release(ConsumerRadiosonde)
	if running.Consumer != ConsumerIsm {
		t.Fatalf("ism should come next, got %+v", running)
	}

	running, _ = tuner.Release(ConsumerIsm)
	if running.Consumer != ConsumerAdsb {
		t.Fatalf("with the queue empty, ADS-B resumes, got %+v", running)
	}
}

func TestReleasingSomethingElseChangesNothing(t *testing.T) {
	tuner := newTestTuner()
	tuner.Request(Claim{Consumer: ConsumerListening})

	if _, changed := tuner.Release(ConsumerAprs); changed {
		t.Error("releasing a consumer that does not hold the tuner should do nothing")
	}
	if tuner.Current().Consumer != ConsumerListening {
		t.Error("listening should still hold the tuner")
	}
}

func TestRetuningTheSameConsumerToAnotherBandIsAChange(t *testing.T) {
	tuner := newTestTuner()
	tuner.Request(Claim{Consumer: ConsumerListening, Band: "fm"})

	_, changed, err := tuner.Request(Claim{Consumer: ConsumerListening, Band: "airband"})
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Error("a band change has to restart the decoder, so it must report as changed")
	}
}

func TestRequestingWhatIsAlreadyRunningIsQuiet(t *testing.T) {
	tuner := newTestTuner()
	tuner.Request(Claim{Consumer: ConsumerListening, Band: "fm"})

	if _, changed, _ := tuner.Request(Claim{Consumer: ConsumerListening, Band: "fm"}); changed {
		t.Error("re-requesting the running claim must not restart the decoder")
	}
}

func TestAnUnknownConsumerIsRefused(t *testing.T) {
	if _, _, err := newTestTuner().Request(Claim{Consumer: "cb-radio"}); err == nil {
		t.Error("an unknown consumer should be refused")
	}
}

// A scheduled claim (a satellite pass, a sonde window) ends on its own.
func TestAnExpiredClaimHandsTheTunerBack(t *testing.T) {
	now := time.Unix(1000, 0)
	tuner := NewTuner(func() time.Time { return now })

	tuner.Request(Claim{Consumer: ConsumerRadiosonde, Until: now.Add(time.Hour)})
	if _, changed := tuner.Expire(); changed {
		t.Fatal("the window is still open")
	}

	now = now.Add(2 * time.Hour)
	running, changed := tuner.Expire()
	if !changed || running.Consumer != ConsumerAdsb {
		t.Fatalf("an expired claim should fall back to ADS-B, got %+v", running)
	}
}

func TestExpiryAlsoClearsStaleWaitingClaims(t *testing.T) {
	now := time.Unix(1000, 0)
	tuner := NewTuner(func() time.Time { return now })

	tuner.Request(Claim{Consumer: ConsumerListening})
	tuner.Request(Claim{Consumer: ConsumerRadiosonde, Until: now.Add(time.Minute)})

	now = now.Add(time.Hour)
	tuner.Expire()

	if waiting := tuner.Waiting(); len(waiting) != 0 {
		t.Errorf("a sonde window that passed while queued is stale, got %v", waiting)
	}
}

func TestModeCommandsMapOntoConsumers(t *testing.T) {
	cases := []struct {
		mode    Mode
		submode string
		want    Consumer
		ok      bool
	}{
		{Sigint, "adsb", ConsumerAdsb, true},
		{Sigint, "ism", ConsumerIsm, true},
		{Comms, "fm", ConsumerListening, true},
		{Comms, "dab", ConsumerListening, true},
		{Sigint, Off, "", false},
		{Lumen, "cozy", "", false}, // the light does not want the tuner
	}
	for _, c := range cases {
		got, ok := ConsumerForMode(c.mode, c.submode)
		if ok != c.ok || got != c.want {
			t.Errorf("%s/%s: expected %q/%v, got %q/%v", c.mode, c.submode, c.want, c.ok, got, ok)
		}
	}
}

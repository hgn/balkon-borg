package main

import (
	"strings"
	"testing"
	"time"
)

func stormSample(ts time.Time, p float64) EnvSample {
	return EnvSample{TS: Timestamp(ts), P: p}
}

// stormHistory builds a newest-first sample list at a fixed interval, matching what
// EnvHistory.Samples returns: index 0 is "now", index i is i*interval further back.
func stormHistory(end time.Time, interval time.Duration, count int,
	pressureAt func(i int) float64) []EnvSample {
	out := make([]EnvSample, count)
	for i := 0; i < count; i++ {
		out[i] = stormSample(end.Add(-time.Duration(i)*interval), pressureAt(i))
	}
	return out
}

func TestStormNoWarningOnEmptyOrSingleSampleHistory(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	sd := NewStormDetector(1.0, 3, 15*time.Minute, time.Hour, fixedClock(now))

	if fire, _ := sd.Check(nil); fire {
		t.Error("empty history must not fire")
	}
	if fire, _ := sd.Check([]EnvSample{stormSample(now, 1013)}); fire {
		t.Error("a single sample must not fire")
	}
}

func TestStormRisingPressureDoesNotFire(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	sd := NewStormDetector(1.0, 3, 15*time.Minute, time.Hour, fixedClock(now))

	// Pressure three hours ago was lower than now: it has been rising, not falling.
	h := stormHistory(now, time.Minute, 200, func(i int) float64 {
		if i >= 180 {
			return 1010.0
		}
		return 1011.0
	})
	if fire, _ := sd.Check(h); fire {
		t.Error("rising pressure must not fire")
	}
}

func TestStormSustainedDropFires(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	sd := NewStormDetector(1.0, 3, 15*time.Minute, time.Hour, fixedClock(now))

	// 4 hPa over exactly 3 hours: well past the 1 hPa/h rule of thumb.
	h := stormHistory(now, time.Minute, 200, func(i int) float64 {
		if i >= 180 {
			return 1017.0
		}
		return 1013.0
	})
	fire, drop := sd.Check(h)
	if !fire {
		t.Fatal("expected a warning")
	}
	if drop != 4.0 {
		t.Errorf("expected a 4 hPa drop, got %.2f", drop)
	}
}

// The failure mode named in the task: the unit was off for two days, and the first
// sample after boot lands right next to one from before the outage. That must not
// read as a catastrophic pressure drop.
func TestStormGapInHistoryDoesNotReadAsADrop(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	sd := NewStormDetector(1.0, 3, 15*time.Minute, time.Hour, fixedClock(now))

	h := []EnvSample{
		stormSample(now, 995),                     // just booted, pressure now low
		stormSample(now.Add(-48*time.Hour), 1020), // last sample before the outage
	}
	if fire, _ := sd.Check(h); fire {
		t.Error("a two-day gap must not be read as a fast pressure drop")
	}
}

// Gaps that stay under MaxGap (a coarser cadence, a couple of missed ESP readings)
// must not block a genuine drop from being detected; only a gap past MaxGap should.
func TestStormGapsWithinToleranceStillAllowDetection(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	sd := NewStormDetector(1.0, 3, 15*time.Minute, time.Hour, fixedClock(now))

	// Sparser sampling than the usual one-per-minute (every 10 minutes here) still
	// counts as continuous: every consecutive gap is well under MaxGap.
	h := stormHistory(now, 10*time.Minute, 19, func(i int) float64 {
		if i >= 18 {
			return 1017.0
		}
		return 1013.0
	})
	fire, drop := sd.Check(h)
	if !fire {
		t.Fatal("gaps within MaxGap should not block a genuine drop from being detected")
	}
	if drop != 4.0 {
		t.Errorf("expected a 4 hPa drop, got %.2f", drop)
	}
}

func TestStormCooldownSuppressesRepeatedWarnings(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	sd := NewStormDetector(1.0, 3, 15*time.Minute, time.Hour, func() time.Time { return now })
	h := stormHistory(now, time.Minute, 200, func(i int) float64 {
		if i >= 180 {
			return 1017.0
		}
		return 1013.0
	})

	if fire, _ := sd.Check(h); !fire {
		t.Fatal("expected the first check to fire")
	}
	if fire, _ := sd.Check(h); fire {
		t.Error("still inside the cooldown, must not fire again for the same weather")
	}

	// Time moves and so does the history: samples keep arriving, so the check runs
	// against fresh data rather than the same frozen ring an hour and a half later.
	now = now.Add(90 * time.Minute) // cooldown is an hour
	later := stormHistory(now, time.Minute, 200, func(i int) float64 {
		if i >= 180 {
			return 1017.0
		}
		return 1013.0
	})
	if fire, _ := sd.Check(later); !fire {
		t.Error("the cooldown has elapsed, expected a warning again")
	}
}

func TestStormThresholdBoundary(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)

	// Exactly 3 hPa over exactly 3 hours is exactly the 1 hPa/h rule: it should fire.
	atThreshold := NewStormDetector(1.0, 3, 15*time.Minute, time.Hour, fixedClock(now))
	h := stormHistory(now, time.Minute, 200, func(i int) float64 {
		if i >= 180 {
			return 1013.0
		}
		return 1010.0
	})
	if fire, _ := atThreshold.Check(h); !fire {
		t.Error("a drop exactly at the threshold rate should fire")
	}

	// Just under the rate should not.
	belowThreshold := NewStormDetector(1.0, 3, 15*time.Minute, time.Hour, fixedClock(now))
	h2 := stormHistory(now, time.Minute, 200, func(i int) float64 {
		if i >= 180 {
			return 1012.9
		}
		return 1010.0
	})
	if fire, _ := belowThreshold.Check(h2); fire {
		t.Error("a drop just under the threshold rate should not fire")
	}
}

func TestStormEventTextReadsLikeSomethingAPhoneCanShow(t *testing.T) {
	got := StormEventText(4.2, 3)
	if got == "" {
		t.Fatal("expected a non-empty warning text")
	}
	// German, per the contract; a stray English word here would be a copy-paste bug.
	if !strings.Contains(got, "Sturmwarnung") {
		t.Errorf("expected the German warning to say what it is, got %q", got)
	}
}

// A dead ESP leaves a history that still ends in a real drop. Hours later that is this
// morning's weather, not a warning worth a notification.
func TestStormIgnoresAHistoryThatStoppedGrowing(t *testing.T) {
	now := time.Date(2026, 7, 20, 18, 0, 0, 0, time.UTC)
	d := NewStormDetector(1.0, 3, 15*time.Minute, 6*time.Hour,
		func() time.Time { return now })

	// A textbook drop, but the last reading is six hours old: the sensor went quiet.
	stale := now.Add(-6 * time.Hour)
	history := []EnvSample{}
	for i := 0; i <= 12; i++ {
		ts := stale.Add(-time.Duration(i) * 15 * time.Minute)
		history = append(history, EnvSample{TS: Timestamp(ts), P: 1000 + float64(i)})
	}

	if fire, _ := d.Check(history); fire {
		t.Error("a history that stopped growing must not raise a warning")
	}
}

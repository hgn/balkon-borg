package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func fptr(v float64) *float64 { return &v }

// --- parsing -------------------------------------------------------------------------

// A real-looking weather sensor line: model, integer id, battery flag, temperature and
// humidity. This is the common case rtl_433 produces for the 868 MHz half of the hop.
const weatherLine = `{"time":"2026-07-20 21:14:03","model":"Nexus-TH","id":20,"channel":1,` +
	`"battery_ok":1,"temperature_C":21.4,"humidity":55}`

// A real-looking TPMS line: string id (hex), pressure_kPa is the field that marks it as
// a tyre reading.
const tpmsLine = `{"time":"2026-07-20 21:15:10","model":"Renault","type":"TPMS",` +
	`"id":"1a2b3c4d","status":0,"pressure_kPa":220.5,"temperature_C":24.0,"mic":"CRC"}`

// A sensor that transmits nothing but a battery flag — the task's named edge case.
const batteryOnlyLine = `{"time":"2026-07-20 21:16:00","model":"Secplus-v1","id":5,"battery_ok":1}`

func TestParseRtl433LineWeatherSensor(t *testing.T) {
	r, err := ParseRtl433Line(weatherLine)
	if err != nil {
		t.Fatal(err)
	}
	if r.Model != "Nexus-TH" || r.ID != "20" {
		t.Errorf("model/id not parsed: %+v", r)
	}
	if r.TemperatureC == nil || *r.TemperatureC != 21.4 {
		t.Errorf("temperature not parsed: %+v", r)
	}
	if r.HumidityPct == nil || *r.HumidityPct != 55 {
		t.Errorf("humidity not parsed: %+v", r)
	}
	if r.BatteryOK == nil || !*r.BatteryOK {
		t.Errorf("battery flag not parsed: %+v", r)
	}
	if r.PressureKPa != nil {
		t.Errorf("a weather sensor must not carry a pressure field, got %+v", r)
	}
	if r.IsTPMS() {
		t.Error("a weather sensor is not a TPMS reading")
	}
}

func TestParseRtl433LineTPMS(t *testing.T) {
	r, err := ParseRtl433Line(tpmsLine)
	if err != nil {
		t.Fatal(err)
	}
	if r.Model != "Renault" || r.ID != "1a2b3c4d" {
		t.Errorf("model/id not parsed: %+v", r)
	}
	if r.PressureKPa == nil || *r.PressureKPa != 220.5 {
		t.Errorf("pressure not parsed: %+v", r)
	}
	if !r.IsTPMS() {
		t.Error("a reading with pressure_kPa must be a TPMS reading")
	}
}

// The named edge case: a sensor sending nothing but a battery flag must still parse,
// with everything else absent rather than zero (a zero temperature would be a lie).
func TestParseRtl433LineBatteryOnly(t *testing.T) {
	r, err := ParseRtl433Line(batteryOnlyLine)
	if err != nil {
		t.Fatal(err)
	}
	if r.Model != "Secplus-v1" || r.ID != "5" {
		t.Errorf("model/id not parsed: %+v", r)
	}
	if r.BatteryOK == nil || !*r.BatteryOK {
		t.Errorf("battery flag not parsed: %+v", r)
	}
	if r.TemperatureC != nil || r.HumidityPct != nil || r.PressureKPa != nil {
		t.Errorf("absent fields must stay nil, not zero, got %+v", r)
	}
}

// A model rtl_433 has never been told about by name (no allowlist here: rtl_433 ships
// dozens of decoders and the list changes every release) must still parse normally.
func TestParseRtl433LineUnknownModelStillParses(t *testing.T) {
	line := `{"model":"Some-Future-Decoder-9000","id":"ff","temperature_C":18.2}`
	r, err := ParseRtl433Line(line)
	if err != nil {
		t.Fatal(err)
	}
	if r.Model != "Some-Future-Decoder-9000" {
		t.Errorf("expected the unknown model to pass through, got %+v", r)
	}
	if r.IsTPMS() {
		t.Error("no pressure field, must not be classified as TPMS")
	}
}

func TestParseRtl433LineMalformedIsAnError(t *testing.T) {
	if _, err := ParseRtl433Line(`{"model":"Nexus-TH","id":3,`); err == nil {
		t.Fatal("expected a malformed line to be refused")
	}
	if _, err := ParseRtl433Line(`not json at all`); err == nil {
		t.Fatal("expected garbage to be refused")
	}
}

func TestParseRtl433LineWithoutModelIsAnError(t *testing.T) {
	if _, err := ParseRtl433Line(`{"id":"20","temperature_C":21.0}`); err == nil {
		t.Fatal("a line with no model cannot be filed anywhere")
	}
}

// --- the split -------------------------------------------------------------------

func TestSplitAndFeedRoutesByPressureField(t *testing.T) {
	ism := NewRing[IsmEntry](DefaultRingSize)
	tpms := NewRing[TpmsEntry](DefaultRingSize)

	if _, isTPMS, err := SplitAndFeed(weatherLine, "2026-07-20T21:14:03+02:00", 180, ism, tpms); err != nil {
		t.Fatal(err)
	} else if isTPMS {
		t.Error("the weather line must not be classified as TPMS")
	}
	if _, isTPMS, err := SplitAndFeed(tpmsLine, "2026-07-20T21:15:10+02:00", 180, ism, tpms); err != nil {
		t.Fatal(err)
	} else if !isTPMS {
		t.Error("the TPMS line must be classified as TPMS")
	}

	if ism.Len() != 1 {
		t.Fatalf("expected 1 ism entry, got %d", ism.Len())
	}
	if tpms.Len() != 1 {
		t.Fatalf("expected 1 tpms entry, got %d", tpms.Len())
	}
	if ism.Items()[0].Model != "Nexus-TH" {
		t.Errorf("wrong entry landed in the ism ring: %+v", ism.Items()[0])
	}
	if tpms.Items()[0].Model != "Renault" {
		t.Errorf("wrong entry landed in the tpms ring: %+v", tpms.Items()[0])
	}
}

func TestSplitAndFeedReturnsTheParseErrorAndFeedsNothing(t *testing.T) {
	ism := NewRing[IsmEntry](DefaultRingSize)
	tpms := NewRing[TpmsEntry](DefaultRingSize)

	if _, _, err := SplitAndFeed(`garbage`, "2026-07-20T21:14:03+02:00", 180, ism, tpms); err == nil {
		t.Fatal("expected the parse error to surface")
	}
	if ism.Len() != 0 || tpms.Len() != 0 {
		t.Error("a malformed line must not land in either ring")
	}
}

func TestSplitAndFeedMarksALowTyreOnTheEntry(t *testing.T) {
	ism := NewRing[IsmEntry](DefaultRingSize)
	tpms := NewRing[TpmsEntry](DefaultRingSize)
	SplitAndFeed(tpmsLine, "2026-07-20T21:15:10+02:00", 250, ism, tpms) // threshold above the reading

	if !tpms.Items()[0].Low {
		t.Error("220.5 kPa against a 250 kPa threshold should read as low")
	}
}

func TestPayloadsCarryAnEmptyListNotNull(t *testing.T) {
	data, err := json.Marshal(IsmRecentPayload(NewRing[IsmEntry](DefaultRingSize)))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"entries":[]`) {
		t.Errorf("expected an empty list, got %s", data)
	}
	data, err = json.Marshal(TpmsRecentPayload(NewRing[TpmsEntry](DefaultRingSize)))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"entries":[]`) {
		t.Errorf("expected an empty list, got %s", data)
	}
}

func TestIsmRecentPayloadCarriesTheSchemaVersion(t *testing.T) {
	ring := NewRing[IsmEntry](DefaultRingSize)
	ring.Add(IsmEntry{TS: "2026-07-20T21:14:03+02:00", Model: "Nexus-TH"})
	data, err := json.Marshal(IsmRecentPayload(ring))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got["v"] != float64(SchemaVersion) {
		t.Errorf("expected the schema version, got %v", got["v"])
	}
}

// --- the low-tyre threshold and cooldown --------------------------------------------

func makeTPMSReading(model, id string, kpa float64) Rtl433Reading {
	return Rtl433Reading{Model: model, ID: id, PressureKPa: fptr(kpa)}
}

func TestTpmsWatchThresholdBoundary(t *testing.T) {
	now := time.Unix(1000, 0)
	w := NewTpmsWatch(180, time.Hour, func() time.Time { return now })

	if w.Check(makeTPMSReading("Renault", "a", 180.0)) {
		t.Error("exactly at the threshold must not read as low")
	}
	if !w.Check(makeTPMSReading("Renault", "b", 179.9)) {
		t.Error("just under the threshold must read as low")
	}
}

func TestTpmsWatchIgnoresReadingsWithoutPressure(t *testing.T) {
	w := NewTpmsWatch(180, time.Hour, fixedClock(time.Unix(1000, 0)))
	if w.Check(Rtl433Reading{Model: "Nexus-TH", ID: "1"}) {
		t.Error("a reading with no pressure field cannot be a low tyre")
	}
}

func TestTpmsWatchCooldownSuppressesRepeats(t *testing.T) {
	now := time.Unix(1000, 0)
	w := NewTpmsWatch(180, 10*time.Minute, func() time.Time { return now })
	low := makeTPMSReading("Renault", "1a2b3c4d", 150)

	if !w.Check(low) {
		t.Fatal("the first low reading should fire")
	}
	now = now.Add(time.Minute)
	if w.Check(low) {
		t.Error("still inside the cooldown, must not fire again for the same sensor")
	}
	now = now.Add(15 * time.Minute)
	if !w.Check(low) {
		t.Error("after the cooldown it may fire again")
	}
}

// Ids are small integers or short hex strings and are not unique across manufacturers,
// so the cooldown key must include the model.
func TestTpmsWatchDoesNotConfuseSensorsWithTheSameID(t *testing.T) {
	now := time.Unix(1000, 0)
	w := NewTpmsWatch(180, time.Hour, func() time.Time { return now })

	if !w.Check(makeTPMSReading("Renault", "1", 150)) {
		t.Fatal("expected the first car's low tyre to fire")
	}
	if !w.Check(makeTPMSReading("Toyota", "1", 150)) {
		t.Error("a different manufacturer with the same id must fire independently")
	}
}

func TestTpmsEventTextIsGermanAndNamesThePressure(t *testing.T) {
	got := TpmsEventText(makeTPMSReading("Renault", "1a2b3c4d", 150))
	if !strings.Contains(got, "Reifendruck") {
		t.Errorf("expected the German word for tyre pressure, got %q", got)
	}
	if !strings.Contains(got, "150") {
		t.Errorf("expected the pressure figure, got %q", got)
	}
}

// --- the rtl_433 invocation -----------------------------------------------------------

func TestIsmArgsHopsBothBandsWithTheConfiguredInterval(t *testing.T) {
	args := IsmArgs(90)
	joined := strings.Join(args, " ")
	for _, want := range []string{"-f " + IsmBandLow, "-f " + IsmBandHigh, "-H 90", "-F json"} {
		if !strings.Contains(joined, want) {
			t.Errorf("expected %q in the args, got %q", want, joined)
		}
	}
}

func TestIsmArgsFallsBackToTheDefaultHopInterval(t *testing.T) {
	args := IsmArgs(0)
	if !strings.Contains(strings.Join(args, " "), "-H "+strconv.Itoa(DefaultIsmHopIntervalS)) {
		t.Errorf("expected the default hop interval, got %v", args)
	}
}

// --- backoff ---------------------------------------------------------------------

func TestIsmBackoffGrowsAndCaps(t *testing.T) {
	prev := time.Duration(0)
	for attempt := 0; attempt < 10; attempt++ {
		d := ismBackoff(attempt)
		if d < prev {
			t.Fatalf("backoff must not shrink: attempt %d gave %v after %v", attempt, d, prev)
		}
		prev = d
	}
	if got := ismBackoff(1000); got != 5*time.Minute {
		t.Errorf("expected the cap at 5m for a large attempt count, got %v", got)
	}
	if got := ismBackoff(0); got != time.Second {
		t.Errorf("expected 1s for the first attempt, got %v", got)
	}
}

// --- health --------------------------------------------------------------------------

type fakeIsmStatus struct {
	last   time.Time
	reason string
}

func (f fakeIsmStatus) LastReading() time.Time { return f.last }
func (f fakeIsmStatus) Reason() string         { return f.reason }

func tunerOnIsm(now func() time.Time) *Tuner {
	tuner := NewTuner(now)
	tuner.Request(Claim{Consumer: ConsumerIsm, Band: "ism"})
	return tuner
}

func TestIsmProbeOkWhenSomethingElseHoldsTheTuner(t *testing.T) {
	tuner := NewTuner(fixedClock(time.Unix(1000, 0))) // idle default: ADS-B
	status := fakeIsmStatus{}
	probe := IsmProbe(status, tuner, fixedClock(time.Unix(1000, 0)), IsmFreshnessWindow)

	if state, _ := probe(); state != StateOK {
		t.Errorf("ISM not being the active consumer is not a fault, got %s", state)
	}
}

func TestIsmProbeSurfacesASupervisorFailure(t *testing.T) {
	now := fixedClock(time.Unix(1000, 0))
	tuner := tunerOnIsm(now)
	status := fakeIsmStatus{reason: "starting rtl_433: exec: \"rtl_433\": executable file not found"}
	probe := IsmProbe(status, tuner, now, IsmFreshnessWindow)

	state, reason := probe()
	if state != StateDegraded {
		t.Errorf("expected degraded, got %s", state)
	}
	if !strings.Contains(reason, "rtl_433") {
		t.Errorf("expected the failure reason to surface, got %q", reason)
	}
}

func TestIsmProbeDegradesOnStaleData(t *testing.T) {
	now := time.Unix(10_000, 0)
	clock := func() time.Time { return now }
	tuner := tunerOnIsm(clock)

	never := IsmProbe(fakeIsmStatus{}, tuner, clock, time.Minute)
	if state, _ := never(); state != StateMissing {
		t.Errorf("never having seen a reading should read as missing, got %s", state)
	}

	fresh := IsmProbe(fakeIsmStatus{last: now.Add(-10 * time.Second)}, tuner, clock, time.Minute)
	if state, _ := fresh(); state != StateOK {
		t.Errorf("expected ok, got %s", state)
	}

	stale := IsmProbe(fakeIsmStatus{last: now.Add(-10 * time.Minute)}, tuner, clock, time.Minute)
	if state, _ := stale(); state != StateDegraded {
		t.Errorf("expected degraded, got %s", state)
	}
}

// --- process supervision (the seam is what makes this testable without hardware) -----

// fakeProcess simulates one rtl_433 run: a canned stdout and a wait() that blocks until
// the context is cancelled, the way a real long-running process would.
func fakeProcess(output string) processStarter {
	return func(ctx context.Context, args []string) (io.ReadCloser, func() error, error) {
		r := io.NopCloser(strings.NewReader(output))
		wait := func() error { <-ctx.Done(); return nil }
		return r, wait, nil
	}
}

func TestIsmSupervisorFeedsEveryLineToTheCallback(t *testing.T) {
	var mu sync.Mutex
	var got []string
	done := make(chan struct{})

	sup := NewIsmSupervisor(60, func(line string) {
		mu.Lock()
		got = append(got, line)
		if len(got) == 2 {
			close(done)
		}
		mu.Unlock()
	})
	sup.start = fakeProcess("line one\nline two\n")

	sup.Start()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for both lines")
	}
	sup.Stop()

	mu.Lock()
	defer mu.Unlock()
	if len(got) != 2 || got[0] != "line one" || got[1] != "line two" {
		t.Errorf("unexpected lines: %v", got)
	}
}

func TestIsmSupervisorStopIsIdempotentAndStopsTheLoop(t *testing.T) {
	sup := NewIsmSupervisor(60, func(string) {})
	sup.start = fakeProcess("")
	sup.Start()
	sup.Stop()
	sup.Stop() // must not panic or block
	if sup.Running() {
		t.Error("expected Running() to report false after Stop")
	}
}

// A process that fails to start is retried; the failure reason must be visible via
// Reason() until a real reading proves the decoder healthy again.
func TestIsmSupervisorRetriesAndRemembersTheFailureReason(t *testing.T) {
	sup := NewIsmSupervisor(60, func(string) {})
	sup.backoff = func(int) time.Duration { return 0 } // no need to wait out a real backoff

	var attempts int
	var mu sync.Mutex
	secondAttempt := make(chan struct{})
	sup.start = func(ctx context.Context, args []string) (io.ReadCloser, func() error, error) {
		mu.Lock()
		attempts++
		n := attempts
		mu.Unlock()
		if n == 1 {
			return nil, nil, fmt.Errorf("device busy")
		}
		close(secondAttempt)
		return io.NopCloser(strings.NewReader("")), func() error { <-ctx.Done(); return nil }, nil
	}

	sup.Start()
	select {
	case <-secondAttempt:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for the retry")
	}
	sup.Stop()

	if reason := sup.Reason(); !strings.Contains(reason, "device busy") {
		t.Errorf("expected the failure reason to be remembered, got %q", reason)
	}
}

// The freshness signal only moves on an actual decoded reading, not on the process
// merely starting: a process that runs but decodes nothing must still read as quiet.
func TestIsmSupervisorNoteReadingClearsTheFailureReason(t *testing.T) {
	sup := NewIsmSupervisor(60, func(string) {})
	sup.recordFailure("rtl_433 exited: signal: killed")
	if sup.Reason() == "" {
		t.Fatal("expected the failure to be recorded")
	}
	sup.NoteReading(time.Unix(1000, 0))
	if sup.Reason() != "" {
		t.Error("a successful reading should clear the remembered failure")
	}
	if !sup.LastReading().Equal(time.Unix(1000, 0)) {
		t.Errorf("expected the reading time to be recorded, got %v", sup.LastReading())
	}
}

package main

import (
	"encoding/json"
	"math"
	"strings"
	"testing"
	"time"
)

// The balcony, from borg.yaml.
const homeLat, homeLon = 48.1372, 11.5000

func ptr(v float64) *float64 { return &v }

func TestDistanceAndBearingAgainstKnownPoints(t *testing.T) {
	// Due north of home, roughly 11.1 km (0.1° of latitude).
	dist := DistanceKM(homeLat, homeLon, homeLat+0.1, homeLon)
	if math.Abs(dist-11.1) > 0.2 {
		t.Errorf("expected about 11.1 km, got %.2f", dist)
	}
	if b := BearingDeg(homeLat, homeLon, homeLat+0.1, homeLon); math.Abs(b-0) > 0.5 {
		t.Errorf("due north should be ~0°, got %.1f", b)
	}
	if b := BearingDeg(homeLat, homeLon, homeLat, homeLon+0.1); math.Abs(b-90) > 0.5 {
		t.Errorf("due east should be ~90°, got %.1f", b)
	}
	if b := BearingDeg(homeLat, homeLon, homeLat-0.1, homeLon); math.Abs(b-180) > 0.5 {
		t.Errorf("due south should be ~180°, got %.1f", b)
	}
	if b := BearingDeg(homeLat, homeLon, homeLat, homeLon-0.1); math.Abs(b-270) > 0.5 {
		t.Errorf("due west should be ~270°, got %.1f", b)
	}
}

func TestTheSameSpotIsZeroAway(t *testing.T) {
	if d := DistanceKM(homeLat, homeLon, homeLat, homeLon); d > 0.001 {
		t.Errorf("expected 0, got %v", d)
	}
}

func TestBuildSkyKeepsWhatCanBeDrawn(t *testing.T) {
	snap := ReadsbSnapshot{Aircraft: []ReadsbAircraft{
		{Hex: "far", Lat: ptr(49.5), Lon: ptr(11.5)}, // ~150 km
		{Hex: "near", Flight: "DLH1AB  ", Lat: ptr(48.2), Lon: ptr(11.5), AltBaro: 3000.0},
		{Hex: "nopos"}, // heard, no position
		{Hex: "stale", Lat: ptr(48.15), Lon: ptr(11.5), Seen: 300}, // long gone
	}}

	sky := BuildSky(snap, homeLat, homeLon, 50)

	if len(sky) != 1 {
		t.Fatalf("expected only the near aircraft, got %d: %+v", len(sky), sky)
	}
	if sky[0].Hex != "near" {
		t.Errorf("wrong aircraft kept: %+v", sky[0])
	}
	// readsb pads callsigns to a fixed width; the app would render the spaces.
	if sky[0].Flight != "DLH1AB" {
		t.Errorf("callsign not trimmed: %q", sky[0].Flight)
	}
	if sky[0].DistKM <= 0 || sky[0].BearingDeg < 0 {
		t.Errorf("distance and bearing should be computed here, got %+v", sky[0])
	}
}

func TestBuildSkySortsNearestFirst(t *testing.T) {
	snap := ReadsbSnapshot{Aircraft: []ReadsbAircraft{
		{Hex: "b", Lat: ptr(48.30), Lon: ptr(11.5)},
		{Hex: "a", Lat: ptr(48.15), Lon: ptr(11.5)},
		{Hex: "c", Lat: ptr(48.40), Lon: ptr(11.5)},
	}}

	sky := BuildSky(snap, homeLat, homeLon, 100)

	if len(sky) != 3 || sky[0].Hex != "a" || sky[2].Hex != "c" {
		t.Fatalf("expected nearest first, got %+v", sky)
	}
}

// readsb writes "ground" instead of a number for aircraft on the apron.
func TestAltitudeHandlesGroundAndMissing(t *testing.T) {
	if got := altitudeFeet("ground"); got == nil || *got != 0 {
		t.Errorf("ground should read as 0 ft, got %v", got)
	}
	if got := altitudeFeet(12000.0); got == nil || *got != 12000 {
		t.Errorf("expected 12000, got %v", got)
	}
	if got := altitudeFeet(nil); got != nil {
		t.Errorf("an absent altitude stays absent, got %v", got)
	}
}

// An empty sky is an empty list, not a missing field: the app renders "no aircraft"
// from it, and a null would be a parse error on the phone.
func TestSkyPayloadCarriesAnEmptyListNotNull(t *testing.T) {
	data, err := json.Marshal(SkyPayload(nil, time.Unix(1_800_000_000, 0)))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"aircraft":[]`) {
		t.Errorf("expected an empty list, got %s", data)
	}
	var got map[string]any
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"v", "ts", "aircraft"} {
		if _, ok := got[key]; !ok {
			t.Errorf("payload is missing %q", key)
		}
	}
}

// --- the low-pass event -------------------------------------------------------------

func TestLowPassTriggersOnCloseAndLow(t *testing.T) {
	lp := NewLowPass(5000, 10, time.Minute, fixedClock(time.Unix(1000, 0)))

	hits := lp.Check([]Aircraft{
		{Hex: "low", AltFt: ptr(2500), DistKM: 4},
		{Hex: "high", AltFt: ptr(35000), DistKM: 4},
		{Hex: "distant", AltFt: ptr(2000), DistKM: 40},
		{Hex: "unknown-alt", DistKM: 2},
	})

	if len(hits) != 1 || hits[0].Hex != "low" {
		t.Fatalf("expected only the low close one, got %+v", hits)
	}
}

// Without a cooldown a single circling helicopter would fill the event ring by itself.
func TestLowPassDoesNotReportTheSameAircraftTwice(t *testing.T) {
	now := time.Unix(1000, 0)
	lp := NewLowPass(5000, 10, 10*time.Minute, func() time.Time { return now })
	plane := []Aircraft{{Hex: "abc", AltFt: ptr(1200), DistKM: 3}}

	if len(lp.Check(plane)) != 1 {
		t.Fatal("the first pass should trigger")
	}
	now = now.Add(time.Minute)
	if hits := lp.Check(plane); len(hits) != 0 {
		t.Fatalf("still inside the cooldown, got %+v", hits)
	}
	now = now.Add(15 * time.Minute)
	if len(lp.Check(plane)) != 1 {
		t.Error("after the cooldown it may trigger again")
	}
}

func TestEventTextReadsLikeSomethingAPhoneCanShow(t *testing.T) {
	withFlight := Aircraft{Hex: "3c6abc", Flight: "DLH1AB", AltFt: ptr(2400), DistKM: 3.2}
	if got := withFlight.EventText(); !strings.Contains(got, "DLH1AB") ||
		!strings.Contains(got, "2400") {
		t.Errorf("unexpected text: %q", got)
	}
	// Not every aircraft transmits a callsign; the hex is what is left.
	anonymous := Aircraft{Hex: "3c6abc", AltFt: ptr(2400), DistKM: 3.2}
	if got := anonymous.EventText(); !strings.Contains(got, "3c6abc") {
		t.Errorf("expected the hex as a fallback, got %q", got)
	}
}

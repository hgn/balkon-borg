// ADS-B: the sky picture the app's radar draws (U5).
//
// readsb decodes and writes `aircraft.json` (the dump1090/tar1090 format); the arbiter
// reads it, keeps what is within range, computes distance and bearing relative to the
// balcony, and republishes it as one retained snapshot. Retained on purpose: a client
// that connects between two overflights would otherwise see an empty sky.
//
// The parsing and filtering are pure and tested; only the file reading is not.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"time"
)

// ReadsbAircraft is one entry of readsb's aircraft.json. Every field except the hex is
// optional in practice: an aircraft heard once may have a position and nothing else, or
// a callsign and no position at all.
type ReadsbAircraft struct {
	Hex     string   `json:"hex"`
	Flight  string   `json:"flight"`
	Lat     *float64 `json:"lat"`
	Lon     *float64 `json:"lon"`
	AltBaro any      `json:"alt_baro"` // number, or "ground"
	Track   *float64 `json:"track"`
	GS      *float64 `json:"gs"`
	Seen    float64  `json:"seen"` // seconds since this aircraft was last heard
}

type ReadsbSnapshot struct {
	Now      float64          `json:"now"`
	Aircraft []ReadsbAircraft `json:"aircraft"`
}

// Aircraft is what the contract publishes and the app's radar reads.
type Aircraft struct {
	Hex        string   `json:"hex"`
	Flight     string   `json:"flight,omitempty"`
	Lat        float64  `json:"lat"`
	Lon        float64  `json:"lon"`
	AltFt      *float64 `json:"alt_ft,omitempty"`
	Track      *float64 `json:"track,omitempty"`
	GS         *float64 `json:"gs,omitempty"`
	DistKM     float64  `json:"dist_km"`
	BearingDeg float64  `json:"bearing_deg"`
}

// MaxSeenSeconds drops aircraft readsb has not heard from recently. They linger in its
// JSON for a while after leaving, and a radar full of ghosts is worse than an empty one.
const MaxSeenSeconds = 60

// BuildSky turns a readsb snapshot into the contract's payload contents: aircraft with a
// usable position, within range, nearest first.
func BuildSky(snap ReadsbSnapshot, homeLat, homeLon, maxRangeKM float64) []Aircraft {
	out := make([]Aircraft, 0, len(snap.Aircraft))
	for _, a := range snap.Aircraft {
		if a.Lat == nil || a.Lon == nil {
			continue // heard, but no position: nothing to place on a radar
		}
		if a.Seen > MaxSeenSeconds {
			continue
		}
		dist := DistanceKM(homeLat, homeLon, *a.Lat, *a.Lon)
		if maxRangeKM > 0 && dist > maxRangeKM {
			continue
		}
		out = append(out, Aircraft{
			Hex:        a.Hex,
			Flight:     trimCallsign(a.Flight),
			Lat:        *a.Lat,
			Lon:        *a.Lon,
			AltFt:      altitudeFeet(a.AltBaro),
			Track:      a.Track,
			GS:         a.GS,
			DistKM:     round(dist, 2),
			BearingDeg: round(BearingDeg(homeLat, homeLon, *a.Lat, *a.Lon), 1),
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].DistKM < out[j].DistKM })
	return out
}

// SkyPayload is the retained `balkon/adsb/aircraft` message.
func SkyPayload(aircraft []Aircraft, now time.Time) map[string]any {
	if aircraft == nil {
		aircraft = []Aircraft{} // an empty sky is an empty list, not a missing field
	}
	return Envelope(map[string]any{"ts": Timestamp(now), "aircraft": aircraft})
}

// altitudeFeet handles readsb's alt_baro, which is a number in flight, the string
// "ground" on the apron, and absent for an aircraft heard without altitude.
func altitudeFeet(v any) *float64 {
	switch n := v.(type) {
	case float64:
		return &n
	case string:
		if n == "ground" {
			zero := 0.0
			return &zero
		}
	}
	return nil
}

// trimCallsign strips readsb's fixed-width padding: callsigns arrive as "DLH1AB  ".
func trimCallsign(s string) string {
	for len(s) > 0 && s[len(s)-1] == ' ' {
		s = s[:len(s)-1]
	}
	return s
}

func round(v float64, places int) float64 {
	factor := 1.0
	for i := 0; i < places; i++ {
		factor *= 10
	}
	return float64(int64(v*factor+0.5*sign(v))) / factor
}

func sign(v float64) float64 {
	if v < 0 {
		return -1
	}
	return 1
}

// --- the low-pass event (U5) -------------------------------------------------------

// LowPass decides whether an aircraft is worth an event: close, low, and not one we
// just reported. Without the "not again" part a single circling helicopter would fill
// the event ring by itself.
type LowPass struct {
	MaxAltFt  float64
	MaxDistKM float64
	Cooldown  time.Duration
	reported  map[string]time.Time
	now       func() time.Time
}

func NewLowPass(maxAltFt, maxDistKM float64, cooldown time.Duration, now func() time.Time) *LowPass {
	if now == nil {
		now = time.Now
	}
	if cooldown <= 0 {
		cooldown = 10 * time.Minute
	}
	return &LowPass{MaxAltFt: maxAltFt, MaxDistKM: maxDistKM, Cooldown: cooldown,
		reported: map[string]time.Time{}, now: now}
}

// Check returns the aircraft that deserve an event right now.
func (l *LowPass) Check(aircraft []Aircraft) []Aircraft {
	now := l.now()
	var hits []Aircraft
	for _, a := range aircraft {
		if a.AltFt == nil || *a.AltFt > l.MaxAltFt || a.DistKM > l.MaxDistKM {
			continue
		}
		if last, seen := l.reported[a.Hex]; seen && now.Sub(last) < l.Cooldown {
			continue
		}
		l.reported[a.Hex] = now
		hits = append(hits, a)
	}
	// Forget old entries so the map does not grow for the life of the process.
	for hex, t := range l.reported {
		if now.Sub(t) > 24*time.Hour {
			delete(l.reported, hex)
		}
	}
	return hits
}

// EventText is the line that lands in the event ring and, from there, on the phone.
func (a Aircraft) EventText() string {
	name := a.Flight
	if name == "" {
		name = a.Hex
	}
	if a.AltFt == nil {
		return fmt.Sprintf("%s, %.1f km", name, a.DistKM)
	}
	return fmt.Sprintf("%s in %.0f ft, %.1f km", name, *a.AltFt, a.DistKM)
}

// ReadSnapshot reads readsb's aircraft.json. The only part of this file that touches
// the world, and it fails softly: a missing file is a decoder that is not running yet.
func ReadSnapshot(path string) (ReadsbSnapshot, error) {
	var snap ReadsbSnapshot
	data, err := os.ReadFile(path)
	if err != nil {
		return snap, fmt.Errorf("reading %s: %w", path, err)
	}
	if err := json.Unmarshal(data, &snap); err != nil {
		return snap, fmt.Errorf("parsing %s: %w", path, err)
	}
	return snap, nil
}

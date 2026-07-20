// U13: rtl_433 decodes 433/868 MHz neighbourhood sensor traffic while the ISM consumer
// holds the tuner. Two things live here: the pure parsing/splitting/threshold logic
// (tested, no process involved) and the thin process supervisor that actually runs
// rtl_433 (the one part of this file that cannot be tested without an SDR).
//
// The split (rings.go's general SIGINT pattern applied twice): readings that carry
// tyre-pressure fields go to the TPMS ring, everything else to the ISM ring. They are
// functionally different signals to a consumer (a neighbour's weather reading vs. "a
// car just passed"), not one stream with a type field (use-cases.md U13).
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// --- the rtl_433 invocation -------------------------------------------------------

// IsmBandLow and IsmBandHigh are the two European ISM bands rtl_433 hops between.
// TPMS and many cheap 433 MHz sensors sit at IsmBandLow, but most weather stations and
// smart-home gear transmit at IsmBandHigh; a single fixed capture misses one of the two
// worlds (use-cases.md U13 — corrects an earlier "one capture covers both" claim, do
// not undo it).
const (
	IsmBandLow  = "433.92M"
	IsmBandHigh = "868.3M"
)

// DefaultIsmHopIntervalS mirrors use-cases.md's example (`-H 60`): long enough that a
// short burst on either band is not missed entirely by being mid-hop, short enough
// that neither band goes quiet for more than a minute at a time.
const DefaultIsmHopIntervalS = 60

// IsmArgs builds the rtl_433 command line: frequency hopping between the two bands and
// one JSON object per line on stdout, which is the shape ParseRtl433Line reads. rtl_433
// picks device 0 by default, which is correct here: this system has exactly one
// RTL-SDR by design (tuner.go).
func IsmArgs(hopIntervalS int) []string {
	if hopIntervalS <= 0 {
		hopIntervalS = DefaultIsmHopIntervalS
	}
	return []string{
		"-f", IsmBandLow,
		"-f", IsmBandHigh,
		"-H", strconv.Itoa(hopIntervalS),
		"-F", "json",
	}
}

// --- parsing -----------------------------------------------------------------------

// Rtl433Reading is one decoded line, normalized from rtl_433's loose JSON schema.
// Everything beyond Model and ID is optional: a sensor may transmit nothing but a
// battery flag, and the next line may be a completely different sensor type with a
// completely different field set.
type Rtl433Reading struct {
	Model        string
	ID           string
	TemperatureC *float64
	HumidityPct  *float64
	PressureKPa  *float64
	BatteryOK    *bool
}

// IsTPMS is the split rule (U13): rtl_433's TPMS decoders are the only ones that emit
// pressure_kPa, so its presence is what tells a tyre-pressure reading apart from a
// weather or smart-home one. Not a model allowlist on purpose: rtl_433 ships dozens of
// TPMS decoders (per-manufacturer) and the list changes with every rtl_433 release, so
// keying on the field it always produces is the stable rule.
func (r Rtl433Reading) IsTPMS() bool { return r.PressureKPa != nil }

// ParseRtl433Line decodes one line of rtl_433's `-F json` output. Defensive by
// necessity: the schema is whatever the sensor that happened to transmit supports, and
// a marginal reception can still produce syntactically valid JSON with junk in it.
// Only `model` is required; everything else degrades to "absent" rather than an error.
func ParseRtl433Line(line string) (Rtl433Reading, error) {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(line), &raw); err != nil {
		return Rtl433Reading{}, fmt.Errorf("not JSON: %w", err)
	}

	model, err := rawJSONString(raw["model"])
	if err != nil || model == "" {
		return Rtl433Reading{}, fmt.Errorf("no usable model field")
	}

	id := ""
	if v, ok := raw["id"]; ok {
		id = rawJSONScalarString(v)
	}

	return Rtl433Reading{
		Model:        model,
		ID:           id,
		TemperatureC: rawJSONFloatPtr(raw["temperature_C"]),
		HumidityPct:  rawJSONFloatPtr(raw["humidity"]),
		PressureKPa:  rawJSONFloatPtr(raw["pressure_kPa"]),
		BatteryOK:    rawJSONBoolPtr(raw["battery_ok"]),
	}, nil
}

func rawJSONString(v json.RawMessage) (string, error) {
	if v == nil {
		return "", nil
	}
	var s string
	if err := json.Unmarshal(v, &s); err != nil {
		return "", err
	}
	return s, nil
}

// rawJSONScalarString turns whatever rtl_433 sent for "id" into a string: some
// decoders use a hex string, most use a plain integer.
func rawJSONScalarString(v json.RawMessage) string {
	var s string
	if err := json.Unmarshal(v, &s); err == nil {
		return s
	}
	var f float64
	if err := json.Unmarshal(v, &f); err == nil {
		if f == math.Trunc(f) {
			return strconv.FormatInt(int64(f), 10)
		}
		return strconv.FormatFloat(f, 'g', -1, 64)
	}
	return ""
}

func rawJSONFloatPtr(v json.RawMessage) *float64 {
	if v == nil {
		return nil
	}
	var f float64
	if err := json.Unmarshal(v, &f); err != nil {
		return nil
	}
	return &f
}

// rawJSONBoolPtr handles battery_ok, which rtl_433 almost always sends as 0/1 but the
// occasional decoder sends as a JSON bool.
func rawJSONBoolPtr(v json.RawMessage) *bool {
	if v == nil {
		return nil
	}
	var f float64
	if err := json.Unmarshal(v, &f); err == nil {
		b := f != 0
		return &b
	}
	var b bool
	if err := json.Unmarshal(v, &b); err == nil {
		return &b
	}
	return nil
}

// --- ring entries and the split ----------------------------------------------------

// IsmEntry is one `balkon/ism/recent` entry: a neighbourhood sensor reading with
// whichever fields it actually sent.
type IsmEntry struct {
	TS           string   `json:"ts"`
	Model        string   `json:"model"`
	ID           string   `json:"id,omitempty"`
	TemperatureC *float64 `json:"temperature_c,omitempty"`
	HumidityPct  *float64 `json:"humidity_pct,omitempty"`
	BatteryOK    *bool    `json:"battery_ok,omitempty"`
}

// TpmsEntry is one `balkon/tpms/recent` entry: a tyre-pressure reading. Low is
// computed here (against the configured threshold) so the app does not need to know
// the threshold to colour a reading.
type TpmsEntry struct {
	TS           string   `json:"ts"`
	Model        string   `json:"model"`
	ID           string   `json:"id,omitempty"`
	PressureKPa  float64  `json:"pressure_kpa"`
	TemperatureC *float64 `json:"temperature_c,omitempty"`
	BatteryOK    *bool    `json:"battery_ok,omitempty"`
	Low          bool     `json:"low"`
}

func (r Rtl433Reading) ismEntry(ts string) IsmEntry {
	return IsmEntry{
		TS: ts, Model: r.Model, ID: r.ID,
		TemperatureC: r.TemperatureC, HumidityPct: r.HumidityPct, BatteryOK: r.BatteryOK,
	}
}

func (r Rtl433Reading) tpmsEntry(ts string, lowKPa float64) TpmsEntry {
	return TpmsEntry{
		TS: ts, Model: r.Model, ID: r.ID, PressureKPa: *r.PressureKPa,
		TemperatureC: r.TemperatureC, BatteryOK: r.BatteryOK, Low: *r.PressureKPa < lowKPa,
	}
}

// SplitAndFeed parses one rtl_433 line and files it into the right ring. Returns the
// parsed reading and whether it went to the TPMS ring, so a caller can run the
// low-tyre check without parsing twice. A parse error is returned unchanged: nothing
// here logs or fails loudly, that is the caller's job (main.go's thin wiring layer).
func SplitAndFeed(line, ts string, lowKPa float64, ism *Ring[IsmEntry], tpms *Ring[TpmsEntry],
) (Rtl433Reading, bool, error) {
	r, err := ParseRtl433Line(line)
	if err != nil {
		return Rtl433Reading{}, false, err
	}
	if r.IsTPMS() {
		tpms.Add(r.tpmsEntry(ts, lowKPa))
		return r, true, nil
	}
	ism.Add(r.ismEntry(ts))
	return r, false, nil
}

// IsmRecentPayload and TpmsRecentPayload are the retained snapshots, the contract's
// `{"v":1,"entries":[…]}` SIGINT ring shape.
func IsmRecentPayload(ring *Ring[IsmEntry]) map[string]any {
	entries := ring.Items()
	if entries == nil {
		entries = []IsmEntry{}
	}
	return Envelope(map[string]any{"entries": entries})
}

func TpmsRecentPayload(ring *Ring[TpmsEntry]) map[string]any {
	entries := ring.Items()
	if entries == nil {
		entries = []TpmsEntry{}
	}
	return Envelope(map[string]any{"entries": entries})
}

// --- the low-tyre event -------------------------------------------------------------

// TpmsWatch decides whether a reading is worth a low-tyre event: below threshold, and
// not one just reported. Same shape as adsb.go's LowPass: without the cooldown, a car
// parked nearby with a sensor that keeps transmitting would fill the event ring by
// itself.
type TpmsWatch struct {
	LowKPa   float64
	Cooldown time.Duration
	reported map[string]time.Time
	now      func() time.Time
}

func NewTpmsWatch(lowKPa float64, cooldown time.Duration, now func() time.Time) *TpmsWatch {
	if now == nil {
		now = time.Now
	}
	if cooldown <= 0 {
		cooldown = 4 * time.Hour
	}
	return &TpmsWatch{LowKPa: lowKPa, Cooldown: cooldown, reported: map[string]time.Time{}, now: now}
}

// Check reports whether this reading should raise an event right now. The key
// combines model and id: rtl_433 ids are small integers or short hex strings that are
// not unique across manufacturers, so the model disambiguates them.
func (w *TpmsWatch) Check(r Rtl433Reading) bool {
	if r.PressureKPa == nil || *r.PressureKPa >= w.LowKPa {
		return false
	}
	key := r.Model + "/" + r.ID
	now := w.now()
	if last, seen := w.reported[key]; seen && now.Sub(last) < w.Cooldown {
		return false
	}
	w.reported[key] = now
	// Forget old entries so the map does not grow for the life of the process.
	for k, t := range w.reported {
		if now.Sub(t) > 24*time.Hour {
			delete(w.reported, k)
		}
	}
	return true
}

// TpmsEventText is the German line that lands in the event ring and, from there, on
// the phone (U13, the app's existing `tpms` notification category).
func TpmsEventText(r Rtl433Reading) string {
	name := r.Model
	if name == "" {
		name = "Reifensensor"
	}
	if r.PressureKPa == nil {
		return fmt.Sprintf("%s: Reifendruck niedrig", name)
	}
	return fmt.Sprintf("%s: Reifendruck niedrig (%.0f kPa)", name, *r.PressureKPa)
}

// --- health --------------------------------------------------------------------------

// IsmFreshnessWindow is how long the feed may stay quiet before the capability reports
// degraded. A suburban neighbourhood usually has a weather station or two transmitting
// every 30-60s on 868 MHz, but rtl_433 only hears half the spectrum at a time while
// hopping, and a genuinely quiet stretch (everyone's sensor between transmissions, no
// passing cars) is normal, not a fault. 15 minutes covers several hop cycles at the
// default 60s interval without crying wolf overnight; this is a guess to check against
// real reception once the SDR is up.
const IsmFreshnessWindow = 15 * time.Minute

// ismStatus is what the health probe needs from the supervisor: a small interface
// rather than the concrete type, so the probe is testable without a process.
type ismStatus interface {
	LastReading() time.Time
	Reason() string
}

// IsmProbe reports on the ISM decoder. Not currently holding the tuner is not a
// problem — SIGINT may be on ADS-B or off, and rtl_433 is not supposed to be running
// then — so that reads as ok. While it should be running, a supervisor failure (repeated
// crashes, could not start) is surfaced directly; otherwise this is exactly
// FreshnessProbe's question, reused rather than reimplemented.
func IsmProbe(status ismStatus, tuner *Tuner, now func() time.Time, maxAge time.Duration) Probe {
	freshness := FreshnessProbe(status.LastReading, now, maxAge, "no data from rtl_433 yet")
	return func() (State, string) {
		if tuner.Current().Consumer != ConsumerIsm {
			return StateOK, ""
		}
		if reason := status.Reason(); reason != "" {
			return StateDegraded, reason
		}
		return freshness()
	}
}

// --- process supervision (untestable without hardware) -----------------------------

// processStarter is the seam: starting rtl_433 and handing back its stdout is the one
// part of this file that cannot run without an SDR. Everything above this line is pure
// and tested in ism_test.go; everything below is deliberately thin.
type processStarter func(ctx context.Context, args []string) (stdout io.ReadCloser, wait func() error, err error)

func execProcessStarter(ctx context.Context, args []string) (io.ReadCloser, func() error, error) {
	cmd := exec.CommandContext(ctx, "rtl_433", args...)
	cmd.Stderr = os.Stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, nil, fmt.Errorf("rtl_433 stdout: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return nil, nil, fmt.Errorf("starting rtl_433: %w", err)
	}
	return stdout, cmd.Wait, nil
}

// minStableUptime is the line between "a hiccup" and "a crash loop". A run that lasted
// at least this long before exiting resets the backoff: a decoder that works fine but
// occasionally dies (a USB glitch) is retried promptly, one that dies immediately every
// time is not retried in a tight loop.
const minStableUptime = 30 * time.Second

// ismBackoff is the restart delay after the Nth consecutive failure: capped
// exponential, so a stick that never comes back is retried patiently instead of
// spun on forever. Pure, so it is tested without waiting for a real sleep.
func ismBackoff(attempt int) time.Duration {
	const max = 5 * time.Minute
	if attempt < 0 {
		attempt = 0
	}
	if attempt > 20 { // 1s<<20 is already far past max; no need to shift further
		attempt = 20
	}
	d := time.Second << attempt
	if d > max {
		d = max
	}
	return d
}

// IsmSupervisor runs rtl_433 for as long as the ISM consumer holds the tuner, restarts
// it with backoff if it dies on its own, and remembers enough state for IsmProbe to
// answer "is it running" and "is data arriving" without touching the process itself.
type IsmSupervisor struct {
	args    []string
	start   processStarter
	backoff func(attempt int) time.Duration
	onLine  func(line string)

	mu          sync.Mutex
	cancel      context.CancelFunc
	running     bool
	lastReading time.Time
	reason      string
}

func NewIsmSupervisor(hopIntervalS int, onLine func(line string)) *IsmSupervisor {
	return &IsmSupervisor{
		args:    IsmArgs(hopIntervalS),
		start:   execProcessStarter,
		backoff: ismBackoff,
		onLine:  onLine,
	}
}

// Start begins supervising rtl_433 if it is not already. Idempotent: applyTuner calls
// this on every mode change, whether or not ISM was already the active consumer.
func (s *IsmSupervisor) Start() {
	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	s.cancel = cancel
	s.running = true
	s.mu.Unlock()
	go s.loop(ctx)
}

// Stop ends supervision and kills whatever is currently running. The SDR cannot be
// shared (tuner.go), so a decoder that outlives its claim breaks every other consumer;
// this must be called both on a tuner handover and on borgd shutdown.
func (s *IsmSupervisor) Stop() {
	s.mu.Lock()
	if !s.running {
		s.mu.Unlock()
		return
	}
	cancel := s.cancel
	s.running = false
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (s *IsmSupervisor) Running() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.running
}

func (s *IsmSupervisor) LastReading() time.Time {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.lastReading
}

func (s *IsmSupervisor) Reason() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.reason
}

// NoteReading marks that a line was successfully decoded. Called by the line handler,
// not the loop itself: a process that is merely running proves nothing, only actual
// data does.
func (s *IsmSupervisor) NoteReading(now time.Time) {
	s.mu.Lock()
	s.lastReading = now
	s.reason = ""
	s.mu.Unlock()
}

func (s *IsmSupervisor) recordFailure(reason string) {
	s.mu.Lock()
	s.reason = reason
	s.mu.Unlock()
	fmt.Fprintf(os.Stderr, "ism: %s\n", reason)
}

// loop starts rtl_433, feeds every stdout line to onLine, and restarts it with backoff
// when it exits — expectedly (Stop was called, ctx is done) or not.
func (s *IsmSupervisor) loop(ctx context.Context) {
	attempt := 0
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		started := time.Now()
		stdout, wait, err := s.start(ctx, s.args)
		if err != nil {
			s.recordFailure(fmt.Sprintf("starting rtl_433: %v", err))
			attempt++
			if !s.sleepBackoff(ctx, attempt) {
				return
			}
			continue
		}

		scanner := bufio.NewScanner(stdout)
		scanner.Buffer(make([]byte, 64*1024), 1<<20)
		for scanner.Scan() {
			if line := strings.TrimSpace(scanner.Text()); line != "" {
				s.onLine(line)
			}
		}
		werr := wait()

		select {
		case <-ctx.Done():
			return
		default:
		}

		if time.Since(started) >= minStableUptime {
			attempt = 0
		} else {
			attempt++
		}
		if werr != nil {
			s.recordFailure(fmt.Sprintf("rtl_433 exited: %v", werr))
		} else {
			s.recordFailure("rtl_433 exited unexpectedly")
		}
		if !s.sleepBackoff(ctx, attempt) {
			return
		}
	}
}

func (s *IsmSupervisor) sleepBackoff(ctx context.Context, attempt int) bool {
	select {
	case <-ctx.Done():
		return false
	case <-time.After(s.backoff(attempt)):
		return true
	}
}

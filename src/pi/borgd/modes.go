// The mode state machine: what the unit is doing, and what it refuses to do.
//
// This is the authority for mode state. Clients (the app, the ESP) send commands and
// render what comes back; the contract's rule is that the state topic is the
// acknowledgement, so nothing here is optimistic.
//
// The one real rule so far: there is a single RTL-SDR, so COMMS and SIGINT cannot run
// at the same time (architecture.md §3/§4). Starting one stops the other. The app
// mirrors this to avoid showing an impossible state for the length of a round trip, but
// the decision belongs here, because the ESP's buttons cause the same collision without
// asking the phone.
package main

import (
	"fmt"
	"sync"
	"time"
)

const Off = "off"

// Submodes per mode, mirroring docs/use-cases.md and the app's contract/submodes.dart.
var Submodes = map[Mode][]string{
	Lumen:  {Off, "ambient", "full", "cozy", "distance-auto", "info-ticker", "disco", "strobe", "police", "visualiser"},
	Comms:  {Off, "fm", "dab", "shortwave", "airband"},
	Sigint: {Off, "adsb", "ism", "aprs", "radiosonde", "spectrum", "captures"},
	Sentry: {Off, "armed"},
}

// tunerRival maps each radio mode to the one it displaces. Modes not in here have no
// rival and displace nothing.
var tunerRival = map[Mode]Mode{Comms: Sigint, Sigint: Comms}

type ModeState struct {
	Submode string `json:"submode"`
	Chan    string `json:"chan,omitempty"`
	Pinned  bool   `json:"pinned"`
	Since   string `json:"since"`
}

func (s ModeState) IsOff() bool { return s.Submode == Off }

type Modes struct {
	mu     sync.Mutex
	now    func() time.Time
	states map[Mode]ModeState
	focus  Mode
}

func NewModes(now func() time.Time) *Modes {
	if now == nil {
		now = time.Now
	}
	m := &Modes{now: now, states: map[Mode]ModeState{}}
	ts := Timestamp(now())
	for _, mode := range AllModes {
		m.states[mode] = ModeState{Submode: Off, Since: ts}
	}
	return m
}

func (m *Modes) Get(mode Mode) ModeState {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.states[mode]
}

func (m *Modes) All() map[Mode]ModeState {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make(map[Mode]ModeState, len(m.states))
	for k, v := range m.states {
		out[k] = v
	}
	return out
}

func knownSubmode(mode Mode, submode string) bool {
	for _, s := range Submodes[mode] {
		if s == submode {
			return true
		}
	}
	return false
}

// Apply applies a command and returns every mode whose state changed, so the caller
// republishes exactly those. A client re-sending the mode it is already in causes no
// republish, which keeps the app's confirmation haptic a confirmation of something
// real.
func (m *Modes) Apply(mode Mode, submode string, chan_ string) ([]Mode, error) {
	if _, ok := Submodes[mode]; !ok {
		return nil, fmt.Errorf("unknown mode %q", mode)
	}
	if !knownSubmode(mode, submode) {
		return nil, fmt.Errorf("%s has no submode %q", mode, submode)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	var changed []Mode
	current := m.states[mode]
	if current.Submode != submode || current.Chan != chan_ {
		m.states[mode] = ModeState{
			Submode: submode,
			Chan:    chan_,
			Pinned:  current.Pinned,
			Since:   Timestamp(m.now()),
		}
		changed = append(changed, mode)
	}

	// One tuner: starting a radio mode stops the other. Turning a mode off displaces
	// nothing, and a rival that is already off is not stopped again.
	if submode != Off {
		if rival, ok := tunerRival[mode]; ok && !m.states[rival].IsOff() {
			m.states[rival] = ModeState{
				Submode: Off,
				Pinned:  m.states[rival].Pinned,
				Since:   Timestamp(m.now()),
			}
			changed = append(changed, rival)
		}
	}
	return changed, nil
}

// SetSentrySubmode writes the SENTRY submode directly, bypassing Apply's
// knownSubmode gate. The ladder's internal states (arming, grace, alarm; sentry.go)
// are real values of balkon/mode/sentry per the contract, but are never something a
// client may request directly — sentry.go enforces that at the command layer — so
// they deliberately do not belong in the client-facing Submodes[Sentry] list that the
// panel cycles through and Apply validates commands against. This is that state
// machine's one write path into the shared mode table.
func (m *Modes) SetSentrySubmode(submode string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	current := m.states[Sentry]
	if current.Submode == submode {
		return false
	}
	m.states[Sentry] = ModeState{Submode: submode, Pinned: current.Pinned, Since: Timestamp(m.now())}
	return true
}

// Pin marks a mode as holding a resource: SENTRY armed pins the camera to Frigate, so
// nothing else can schedule it away while the unit is watching.
func (m *Modes) Pin(mode Mode, pinned bool) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	current := m.states[mode]
	if current.Pinned == pinned {
		return false
	}
	current.Pinned = pinned
	m.states[mode] = current
	return true
}

func (m *Modes) Focus() Mode {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.focus
}

func (m *Modes) SetFocus(mode Mode) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.focus == mode {
		return false
	}
	m.focus = mode
	return true
}

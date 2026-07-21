// The SENTRY escalation ladder (U11): armed watch, person confirmation, entry grace,
// alarm, cooldown.
//
// Pure logic, same shape as modes.go and mixer.go: a small state machine with an
// injected clock, fed discrete events, returning what should happen next. It never
// touches MQTT, WLED, the mixer or Frigate; main.go carries the returned effect out,
// the same split inputs.go's PanelEffect uses for the front panel.
//
// This is the piece use-cases.md calls out as the one worth getting right on paper,
// since there is no camera and no Pi to try it against: the thing that wakes somebody
// at night has to be airtight on its own, not "probably fine".
package main

import (
	"sync"
	"time"
)

// The ladder's submodes, published on balkon/mode/sentry (contract: off·arming·armed·
// grace·alarm). Off is modes.go's shared constant; the other four are internal to the
// ladder and never something a client requests directly (see handleSentryCommand),
// which is why they are not in modes.go's client-facing Submodes[Sentry] list.
const (
	SentryArming = "arming"
	SentryArmed  = "armed"
	SentryGrace  = "grace"
	SentryAlarm  = "alarm"
)

// SentryAlarmText is the German line the phone's event ring shows.
const SentryAlarmText = "SENTRY: Person auf der Terrasse erkannt."

// SentryBeepText is Effector 1's speaker component (U11.3): a short, unambiguous
// "I see you" cue, not a spoken alarm message.
const SentryBeepText = "Peep."

// SentryFlashSeconds is how long the police-light burst runs. WLED reverts itself
// (wled.go's WLEDFlash), so this only has to be short, not exact.
const SentryFlashSeconds = 5

// SentryEffect is what the ladder wants carried out. Several fields may be set at
// once (the alarm transition fires the light, the speaker and the ring together); the
// zero value means "nothing to do", which is the common case (most events just update
// internal bookkeeping and move nothing outwardly visible).
type SentryEffect struct {
	// Submode is non-empty when the published mode state must move to this value.
	Submode string
	// Pin is non-nil when the camera's Vision-axis pin must change (armed pins it to
	// Frigate, disarm releases it).
	Pin *bool
	// Flash requests the WLED police-light burst.
	Flash bool
	// Beep requests the short alarm-priority speaker cue.
	Beep bool
	// Pulse asks for the gentle armed reminder: a brief, dim blink so the unit does
	// not sit there watching without anybody remembering it was switched on.
	Pulse bool
	// Record marks that a security event clip is warranted. Frigate is the one that
	// actually owns event-clip recording (U7: it records on its own detection,
	// pre/post roll, off-site to the nas-Pi); this flag is the hook for whatever
	// borgd needs to nudge once Frigate exists, not a recording command in itself.
	Record bool
	// EventText, non-empty, belongs in the retained event ring for the phone.
	EventText string
}

// SentryLadder is the ladder's state, one instance for the whole unit (there is only
// one SENTRY).
type SentryLadder struct {
	mu  sync.Mutex
	now func() time.Time

	// ExitDelay is arming's fallback: "the armed state becomes live only once the
	// scene has been clear once, or after a fallback exit delay, whichever comes
	// first" (use-cases.md U11). ~60s per the spec: long enough to water the plants
	// and walk out, short enough that arming is never a long, confusing wait.
	ExitDelay time.Duration
	// PersonWindow is how long a radar presence sighting waits for Frigate to confirm
	// a person before the ladder gives up and goes back to plain watching. Long
	// enough for Frigate to wake from its idle ~2 FPS radar-gated schedule and run a
	// few frames past the COCO model (U7); short enough that "something moved but
	// nothing is there" (wind, a cat that never classifies as a person) does not
	// leave the ladder half-triggered for long.
	PersonWindow time.Duration
	// EntryGrace is the confirmed-person window during which disarming stops
	// everything else from firing (U11 "Entry handling"): ~30s, enough to walk up to
	// the panel or open the app.
	EntryGrace time.Duration
	// PulseEvery is how often the armed reminder blinks. Two minutes: often enough to
	// notice from the balcony door, rare enough that it does not become wallpaper.
	PulseEvery time.Duration
	// AlarmCooldown is alarm's fallback, mirroring ExitDelay: "re-fires only after
	// the scene clears or the cooldown lapses" (U11.3), so a lingering person does
	// not strobe/peep on a loop, but the ladder also does not get stuck forever if
	// the radar never reports a clear scene again.
	AlarmCooldown time.Duration

	state    string    // current submode
	deadline time.Time // arming/grace/alarm fallback; zero while off or armed

	// watchingForPerson and personDeadline track the person-confirmation window
	// while armed. They never change the published submode by themselves: presence
	// without a person is invisible from the outside, exactly as U11.2 requires.
	watchingForPerson bool
	personDeadline    time.Time
	nextPulse         time.Time
}

// NewSentryLadder builds the ladder, off, with the given timings. A non-positive duration
// falls back to the documented default, the same defensive pattern NewLowPass and
// NewStormDetector use, so a zero-value Config in a test does not wedge a state
// machine that has nowhere to go.
func NewSentryLadder(now func() time.Time,
	exitDelay, personWindow, entryGrace, alarmCooldown, pulseEvery time.Duration) *SentryLadder {
	if now == nil {
		now = time.Now
	}
	if exitDelay <= 0 {
		exitDelay = 60 * time.Second
	}
	if personWindow <= 0 {
		personWindow = 15 * time.Second
	}
	if entryGrace <= 0 {
		entryGrace = 30 * time.Second
	}
	if alarmCooldown <= 0 {
		alarmCooldown = 60 * time.Second
	}
	if pulseEvery <= 0 {
		pulseEvery = 2 * time.Minute
	}
	return &SentryLadder{
		now:           now,
		ExitDelay:     exitDelay,
		PulseEvery:    pulseEvery,
		PersonWindow:  personWindow,
		EntryGrace:    entryGrace,
		AlarmCooldown: alarmCooldown,
		state:         Off,
	}
}

// State reports the current submode, for the status page and tests.
func (s *SentryLadder) State() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

// enter moves the ladder to a new submode and arms whatever fallback timer that
// submode needs. Callers hold the lock and add any extra effect fields (pin, the
// alarm payload, ...) to the returned value themselves.
func (s *SentryLadder) enter(state string) SentryEffect {
	s.state = state
	s.watchingForPerson = false
	switch state {
	case SentryArming:
		s.deadline = s.now().Add(s.ExitDelay)
	case SentryGrace:
		s.deadline = s.now().Add(s.EntryGrace)
	case SentryAlarm:
		s.deadline = s.now().Add(s.AlarmCooldown)
	default: // Off, SentryArmed: no fallback timer runs
		s.deadline = time.Time{}
	}
	// The armed reminder starts one interval after arriving, not immediately: the
	// transition into armed is itself visible enough.
	if state == SentryArmed {
		s.nextPulse = s.now().Add(s.PulseEvery)
	} else {
		s.nextPulse = time.Time{}
	}
	return SentryEffect{Submode: state}
}

// Arm is the explicit "arm SENTRY" command (U11.1). It only has an effect from off:
// the ladder is never re-armed out from under itself mid-sequence, because there is
// no single sane target state for "arm again" while already arming, watching, in
// entry grace or alarming. Disarm first (always available, see Disarm) to restart it.
func (s *SentryLadder) Arm() SentryEffect {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state != Off {
		return SentryEffect{}
	}
	eff := s.enter(SentryArming)
	pinned := true
	eff.Pin = &pinned
	return eff
}

// Disarm is the explicit "disarm" command, available from anywhere on the ladder
// including mid-alarm: a human override always wins (architecture.md §5), and unlike
// the speaker alarm ladder, SENTRY itself is not the thing that "re-asserts until the
// condition clears" — that rule is about the audio priority once alarm fires, not
// about whether the unit can be switched off.
func (s *SentryLadder) Disarm() SentryEffect {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state == Off {
		return SentryEffect{}
	}
	eff := s.enter(Off)
	pinned := false
	eff.Pin = &pinned
	return eff
}

// PresenceSeen is the radar reporting a person (balkon/presence, present:true). It
// only matters while armed and steady-state watching: during arming it is expected
// (you are still walking out) and handled by the exit-delay logic instead, and during
// grace/alarm the ladder has already moved past "is somebody there" to "somebody
// confirmed". Opens (or refreshes) the person-confirmation window.
func (s *SentryLadder) PresenceSeen() SentryEffect {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state != SentryArmed {
		return SentryEffect{}
	}
	s.watchingForPerson = true
	s.personDeadline = s.now().Add(s.PersonWindow)
	return SentryEffect{}
}

// SceneClear is the radar reporting nobody there (present:false). It plays two roles:
// the "clear once" half of the arming/alarm exit gate (U11's exit handling and U11.3's
// cooldown share the same shape: live again once the scene has been clear once, or a
// fallback elapses), and, while armed, cancelling a person-confirmation window that
// was never going to be confirmed because whatever the radar saw already left.
func (s *SentryLadder) SceneClear() SentryEffect {
	s.mu.Lock()
	defer s.mu.Unlock()
	switch s.state {
	case SentryArming, SentryAlarm:
		return s.enter(SentryArmed)
	case SentryArmed:
		s.watchingForPerson = false
		return SentryEffect{}
	default: // Off, SentryGrace: nothing to do
		return SentryEffect{}
	}
}

// PersonDetected is Frigate confirming a person (balkon/cam/events). It only
// escalates the ladder if there is an open presence window to confirm: while armed
// and PresenceSeen started one within PersonWindow. Anything else — no armed
// presence window open, the window already lapsed, the ladder past armed into
// grace/alarm's cooldown — is a detection with nothing gating it and is ignored. That
// is what keeps a lingering person from re-firing the alarm on every new Frigate
// event during the cooldown, and what keeps a stray Frigate detection with no radar
// wake behind it from doing anything at all.
func (s *SentryLadder) PersonDetected() SentryEffect {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state != SentryArmed || !s.watchingForPerson {
		return SentryEffect{}
	}
	return s.enter(SentryGrace)
}

// Tick is the clock. It advances whichever fallback the current submode is waiting
// on: the person-confirmation window (armed, no submode change either way), the exit
// delay (arming -> armed), entry grace (grace -> alarm, firing the effector), and the
// alarm cooldown (alarm -> armed). Called on a short, regular cadence by main.go; the
// ladder never schedules its own timers, so every deadline is checked here rather
// than firing itself, which is what makes the whole thing replayable in a test.
func (s *SentryLadder) Tick() SentryEffect {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()

	// The armed reminder (user call 2026-07-18): while the unit is watching, blink
	// gently now and then. An armed system nobody remembers arming is one that gets
	// disabled in anger the first time it goes off at the wrong moment. Deliberately
	// checked before the deadline handling below, so a pulse is never swallowed by a
	// state transition happening in the same tick.
	if s.state == SentryArmed && s.PulseEvery > 0 && !now.Before(s.nextPulse) {
		s.nextPulse = now.Add(s.PulseEvery)
		return SentryEffect{Pulse: true}
	}

	if s.state == SentryArmed && s.watchingForPerson && !now.Before(s.personDeadline) {
		// Presence without a person confirmation inside the window: fall back to
		// plain watching. Invisible from the outside, same submode throughout.
		s.watchingForPerson = false
	}

	if s.deadline.IsZero() || now.Before(s.deadline) {
		return SentryEffect{}
	}
	switch s.state {
	case SentryArming:
		return s.enter(SentryArmed)
	case SentryGrace:
		return s.fireAlarm()
	case SentryAlarm:
		return s.enter(SentryArmed)
	default:
		return SentryEffect{}
	}
}

// fireAlarm is Effector 1 (U11.3): flash, beep, record, push. Called with the lock
// already held.
func (s *SentryLadder) fireAlarm() SentryEffect {
	eff := s.enter(SentryAlarm)
	eff.Flash = true
	eff.Beep = true
	eff.Record = true
	eff.EventText = SentryAlarmText
	return eff
}

// One RTL-SDR, six appetites.
//
// ADS-B, rtl_433, APRS, radiosondes, FM/DAB/airband listening and the spectrum view all
// want the same stick. This decides who has it, in one place, as a table of claims with
// priorities. The decoders themselves are small once this is settled, which is why it
// comes first.
//
// Rules that were already fixed elsewhere and are implemented here:
//   - ADS-B is the idle default: whenever nothing else claims the tuner, it runs.
//   - User-initiated listening displaces observation.
//   - The antenna is a manual compromise (docs/build-notes.md). Switching bands retunes
//     the tuner, not the hardware, so the unit can only ask the user to extend the whip.
//
// Pure logic, no processes: `Tuner` says what should be running, `sdr.go` makes it so.
package main

import (
	"fmt"
	"sort"
	"sync"
	"time"
)

// Consumer is something that wants the tuner.
type Consumer string

const (
	ConsumerAdsb       Consumer = "adsb"
	ConsumerIsm        Consumer = "ism" // rtl_433: weather, smart home, tyre sensors
	ConsumerAprs       Consumer = "aprs"
	ConsumerRadiosonde Consumer = "radiosonde"
	ConsumerListening  Consumer = "listening" // FM/DAB+/airband/shortwave, user-initiated
	ConsumerSpectrum   Consumer = "spectrum"  // user-initiated
)

// tunerPriority: higher wins. Observation sits at the bottom, the user at the top, and
// ADS-B lowest of all because it is what runs when nobody wants anything.
var tunerPriority = map[Consumer]int{
	ConsumerAdsb:       10,
	ConsumerIsm:        20,
	ConsumerAprs:       20,
	ConsumerRadiosonde: 30, // twice a day, and missing a sonde means waiting twelve hours
	ConsumerSpectrum:   80,
	ConsumerListening:  90,
}

// IdleConsumer is what the tuner falls back to when every claim is released.
const IdleConsumer = ConsumerAdsb

// Claim is a request for the tuner.
type Claim struct {
	Consumer Consumer
	// Band is what the decoder tunes to, used for the antenna announcement.
	Band string
	// Until bounds a scheduled claim (a satellite pass, a sonde window). Zero means
	// "until released".
	Until time.Time
}

// Tuner tracks who holds the stick and who is waiting.
type Tuner struct {
	mu      sync.Mutex
	now     func() time.Time
	current *Claim
	since   time.Time
	waiting map[Consumer]Claim
}

func NewTuner(now func() time.Time) *Tuner {
	if now == nil {
		now = time.Now
	}
	t := &Tuner{now: now, waiting: map[Consumer]Claim{}}
	t.current = &Claim{Consumer: IdleConsumer}
	t.since = now()
	return t
}

// Request asks for the tuner. It returns what should now be running, and whether that
// is a change from before, so the caller can restart exactly one decoder.
func (t *Tuner) Request(c Claim) (running Claim, changed bool, err error) {
	t.mu.Lock()
	defer t.mu.Unlock()

	if _, known := tunerPriority[c.Consumer]; !known {
		return *t.current, false, fmt.Errorf("unknown tuner consumer %q", c.Consumer)
	}
	if t.current != nil && t.current.Consumer == c.Consumer && t.current.Band == c.Band {
		return *t.current, false, nil
	}
	// A losing claim is remembered rather than dropped: when the winner releases, the
	// tuner should go back to what was interrupted, not to the idle default.
	if t.current != nil && tunerPriority[c.Consumer] < tunerPriority[t.current.Consumer] {
		t.waiting[c.Consumer] = c
		return *t.current, false, nil
	}
	if t.current != nil && t.current.Consumer != IdleConsumer {
		t.waiting[t.current.Consumer] = *t.current
	}
	delete(t.waiting, c.Consumer)
	t.current, t.since = &c, t.now()
	return c, true, nil
}

// Release gives the tuner up. The highest-priority waiting claim takes over, or ADS-B
// resumes: the stick is never idle, since listening for aircraft costs nothing extra.
func (t *Tuner) Release(consumer Consumer) (running Claim, changed bool) {
	t.mu.Lock()
	defer t.mu.Unlock()

	delete(t.waiting, consumer)
	if t.current == nil || t.current.Consumer != consumer {
		return *t.current, false
	}
	next := t.pickWaitingLocked()
	t.current, t.since = &next, t.now()
	return next, true
}

// Expire drops claims whose window has passed (a satellite pass that is over). Returns
// the new state if it changed.
func (t *Tuner) Expire() (running Claim, changed bool) {
	t.mu.Lock()
	defer t.mu.Unlock()

	now := t.now()
	for consumer, claim := range t.waiting {
		if !claim.Until.IsZero() && now.After(claim.Until) {
			delete(t.waiting, consumer)
		}
	}
	if t.current == nil || t.current.Until.IsZero() || !now.After(t.current.Until) {
		return *t.current, false
	}
	next := t.pickWaitingLocked()
	t.current, t.since = &next, t.now()
	return next, true
}

func (t *Tuner) pickWaitingLocked() Claim {
	best := Claim{Consumer: IdleConsumer}
	bestPriority := -1
	for _, claim := range t.waiting {
		if p := tunerPriority[claim.Consumer]; p > bestPriority {
			best, bestPriority = claim, p
		}
	}
	delete(t.waiting, best.Consumer)
	return best
}

func (t *Tuner) Current() Claim {
	t.mu.Lock()
	defer t.mu.Unlock()
	return *t.current
}

// Waiting lists the queued consumers, highest priority first. The status page shows
// this, because "why is there no ADS-B right now" has to be answerable at a glance.
func (t *Tuner) Waiting() []Consumer {
	t.mu.Lock()
	defer t.mu.Unlock()

	out := make([]Consumer, 0, len(t.waiting))
	for consumer := range t.waiting {
		out = append(out, consumer)
	}
	sort.Slice(out, func(i, j int) bool {
		return tunerPriority[out[i]] > tunerPriority[out[j]]
	})
	return out
}

// Since is when the current consumer took over.
func (t *Tuner) Since() time.Time {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.since
}

// ConsumerForMode maps a mode command onto a tuner consumer, which is how the app's
// SIGINT and COMMS submodes reach this table.
func ConsumerForMode(mode Mode, submode string) (Consumer, bool) {
	if submode == Off {
		return "", false
	}
	switch mode {
	case Comms:
		return ConsumerListening, true
	case Sigint:
		switch submode {
		case "adsb":
			return ConsumerAdsb, true
		case "ism":
			return ConsumerIsm, true
		case "aprs":
			return ConsumerAprs, true
		case "radiosonde":
			return ConsumerRadiosonde, true
		case "spectrum":
			return ConsumerSpectrum, true
		}
	}
	return "", false
}

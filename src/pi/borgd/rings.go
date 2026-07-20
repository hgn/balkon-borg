// Ring buffers and the retained snapshots built from them.
//
// The pattern that makes a periodically-connecting phone see history instead of a blank
// screen: every feed keeps its last N entries in RAM and mirrors them to a retained
// topic, so a client that subscribes gets the picture immediately rather than waiting
// for the next event. For a radiosonde that next event is twelve hours away.
//
// Pure logic. Publishing is somebody else's job; this decides *what* the payload is and
// *when* it is worth sending.
package main

import (
	"sync"
	"time"
)

// DefaultRingSize is the SIGINT ring-buffer convention from the contract: the last ~50
// entries, newest first. Big enough to be a history, small enough to stay a message.
const DefaultRingSize = 50

// EventRingSize is smaller: the app diffs this ring to raise notifications, and twenty
// events is more than a phone that wakes every half hour can have missed.
const EventRingSize = 20

// Ring is a bounded, newest-first buffer.
type Ring[T any] struct {
	mu    sync.Mutex
	items []T
	cap   int
}

func NewRing[T any](capacity int) *Ring[T] {
	if capacity <= 0 {
		capacity = DefaultRingSize
	}
	return &Ring[T]{cap: capacity, items: make([]T, 0, capacity)}
}

// Add puts an entry at the front and evicts the oldest once full.
func (r *Ring[T]) Add(item T) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.items = append([]T{item}, r.items...)
	if len(r.items) > r.cap {
		r.items = r.items[:r.cap]
	}
}

// Items returns a copy, newest first. A copy on purpose: the caller marshals it while
// the feed keeps writing.
func (r *Ring[T]) Items() []T {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]T(nil), r.items...)
}

func (r *Ring[T]) Len() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.items)
}

func (r *Ring[T]) Reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.items = r.items[:0]
}

// Coalescer answers "should I publish now?".
//
// A feed at 1 Hz mirrored to a retained topic would write a retained message every
// second forever, which is a lot of broker churn and SD writes for data nobody reads
// between two app launches. So: publish at most every `min` interval while dirty, and
// always publish the first change after a quiet period so a single event still shows up
// immediately.
type Coalescer struct {
	mu       sync.Mutex
	now      func() time.Time
	min      time.Duration
	dirty    bool
	lastSent time.Time
}

func NewCoalescer(min time.Duration, now func() time.Time) *Coalescer {
	if now == nil {
		now = time.Now
	}
	return &Coalescer{min: min, now: now}
}

// Touch records that the underlying data changed.
func (c *Coalescer) Touch() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.dirty = true
}

// Due reports whether a publish is warranted right now, and marks it as done if so.
func (c *Coalescer) Due() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.dirty {
		return false
	}
	now := c.now()
	if !c.lastSent.IsZero() && now.Sub(c.lastSent) < c.min {
		return false
	}
	c.dirty = false
	c.lastSent = now
	return true
}

// --- environment history (U4) ----------------------------------------------------

// EnvSample is one minute of weather, as the app charts it.
type EnvSample struct {
	TS string  `json:"ts"`
	T  float64 `json:"t"`
	H  float64 `json:"h"`
	P  float64 `json:"p"`
}

// EnvHistory turns the ESP's live values into the retained history.
//
// The ESP publishes each reading on its own topic whenever it feels like it; the app
// wants evenly spaced samples with timestamps. So values are held as "latest known" and
// committed on a fixed cadence.
type EnvHistory struct {
	mu       sync.Mutex
	ring     *Ring[EnvSample]
	now      func() time.Time
	interval time.Duration
	last     time.Time
	t, h, p  float64
	seen     bool
}

func NewEnvHistory(hours int, interval time.Duration, now func() time.Time) *EnvHistory {
	if now == nil {
		now = time.Now
	}
	if interval <= 0 {
		interval = time.Minute
	}
	samples := int(time.Duration(hours) * time.Hour / interval)
	if samples <= 0 {
		samples = 60
	}
	return &EnvHistory{ring: NewRing[EnvSample](samples), now: now, interval: interval}
}

// Observe records a live reading. `field` is one of t, h, p.
func (e *EnvHistory) Observe(field string, value float64) {
	e.mu.Lock()
	defer e.mu.Unlock()
	switch field {
	case "t":
		e.t = value
	case "h":
		e.h = value
	case "p":
		e.p = value
	default:
		return
	}
	e.seen = true
}

// Commit appends a sample if the cadence is due and the clock can be trusted.
//
// clockOK gates timestamped persistence: before the first NTP sync the Pi thinks it is
// 1970, and a history stamped that way is worse than a gap, because the gap is obvious
// and the wrong timestamps are not.
func (e *EnvHistory) Commit(clockOK bool) bool {
	e.mu.Lock()
	defer e.mu.Unlock()

	if !e.seen || !clockOK {
		return false
	}
	now := e.now()
	if !e.last.IsZero() && now.Sub(e.last) < e.interval {
		return false
	}
	e.last = now
	e.ring.Add(EnvSample{TS: Timestamp(now), T: e.t, H: e.h, P: e.p})
	return true
}

func (e *EnvHistory) Samples() []EnvSample { return e.ring.Items() }

// Payload is the retained `balkon/env/recent` message. Oldest first here, because it is
// a chart and the app draws left to right; the SIGINT rings are newest-first lists,
// which is a different shape for a different reading.
func (e *EnvHistory) Payload() map[string]any {
	items := e.ring.Items()
	ordered := make([]EnvSample, 0, len(items))
	for i := len(items) - 1; i >= 0; i-- {
		ordered = append(ordered, items[i])
	}
	return Envelope(map[string]any{"samples": ordered})
}

// --- events ----------------------------------------------------------------------

// EventCategory matches what the app's notification settings switch on.
type EventCategory string

const (
	CategorySecurity EventCategory = "security"
	CategoryBird     EventCategory = "bird"
	CategoryAircraft EventCategory = "aircraft"
	CategoryStorm    EventCategory = "storm"
	CategoryTPMS     EventCategory = "tpms"
)

type Event struct {
	TS       string        `json:"ts"`
	Category EventCategory `json:"category"`
	Text     string        `json:"text"`
}

// Events is the retained ring the app diffs to raise notifications. That makes it the
// most consequence-carrying topic in the system: an entry that never lands is a
// notification the user never gets.
type Events struct {
	ring *Ring[Event]
	now  func() time.Time
}

func NewEvents(now func() time.Time) *Events {
	if now == nil {
		now = time.Now
	}
	return &Events{ring: NewRing[Event](EventRingSize), now: now}
}

// Add records an event. Returns false when the clock is not trusted yet: an event with
// a 1970 timestamp would sort to the bottom of the app's log forever.
func (e *Events) Add(category EventCategory, text string, clockOK bool) bool {
	if !clockOK {
		return false
	}
	e.ring.Add(Event{TS: Timestamp(e.now()), Category: category, Text: text})
	return true
}

func (e *Events) Items() []Event { return e.ring.Items() }

// Payload is the retained `balkon/event/recent` message, newest first per the contract.
func (e *Events) Payload() map[string]any {
	return Envelope(map[string]any{"events": e.ring.Items()})
}

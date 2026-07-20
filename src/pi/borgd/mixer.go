// Who gets the speaker.
//
// There is one speaker and several things that want it: the radio plays for hours,
// an announcement interrupts for two seconds, talk-down takes it for the length of a
// message, an alarm outranks everything. The rules are a table rather than conditionals
// scattered across the codebase, so a fourth consumer is a row and not a rewrite.
//
// Pure logic: this decides *who* may play, not *how* to play it. The playback itself
// lives in audio.go, which is the part that cannot be tested without a sound card.
package main

import (
	"fmt"
	"sort"
	"sync"
	"time"
)

// Source is something that wants the speaker.
type Source string

const (
	SourceRadio        Source = "radio"        // COMMS listening, long-running
	SourceBird         Source = "bird"         // BirdNET wants the *microphone*, see below
	SourceAnnouncement Source = "announcement" // TTS: "Borg online", antenna hints
	SourceTalkdown     Source = "talkdown"     // U21: a message from the phone
	SourceAlarm        Source = "alarm"        // U11: SENTRY effector
)

// priority decides who wins when two sources want the speaker at once. Higher wins;
// equal priority means the incumbent keeps it, because interrupting something with an
// equally important thing is just noise.
var priority = map[Source]int{
	SourceRadio:        10,
	SourceAnnouncement: 50,
	SourceTalkdown:     60,
	SourceAlarm:        100,
}

// resumable sources are restarted after a higher-priority one finishes. A radio
// programme is resumed; an announcement that got cut off is stale by then and is not.
var resumable = map[Source]bool{
	SourceRadio: true,
}

// Grant is what the caller does with a claim: play it, or don't.
type Grant struct {
	Granted bool
	// Preempted is the source that had the speaker and lost it, if any.
	Preempted Source
	// Reason explains a refusal, for the log.
	Reason string
}

type Mixer struct {
	mu      sync.Mutex
	now     func() time.Time
	current Source
	since   time.Time
	// suspended holds resumable sources that were preempted, newest first.
	suspended []Source
}

func NewMixer(now func() time.Time) *Mixer {
	if now == nil {
		now = time.Now
	}
	return &Mixer{now: now}
}

// Claim asks for the speaker on behalf of a source.
func (m *Mixer) Claim(src Source) Grant {
	m.mu.Lock()
	defer m.mu.Unlock()

	if _, known := priority[src]; !known {
		return Grant{Reason: fmt.Sprintf("unknown audio source %q", src)}
	}
	if m.current == src {
		return Grant{Granted: true} // already playing, nothing to do
	}
	if m.current == "" {
		m.current, m.since = src, m.now()
		return Grant{Granted: true}
	}
	if priority[src] <= priority[m.current] {
		return Grant{Reason: fmt.Sprintf("%s holds the speaker", m.current)}
	}

	preempted := m.current
	if resumable[preempted] {
		m.suspended = append([]Source{preempted}, m.suspended...)
	}
	m.current, m.since = src, m.now()
	return Grant{Granted: true, Preempted: preempted}
}

// Release hands the speaker back. Returns the source that should resume, if any: the
// radio comes back on its own after an announcement, which is the behaviour that makes
// interruptions feel like interruptions rather than like the radio breaking.
func (m *Mixer) Release(src Source) (resume Source, ok bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.current != src {
		return "", false // releasing something you do not hold is a no-op, not an error
	}
	m.current, m.since = "", time.Time{}
	if len(m.suspended) > 0 {
		resume = m.suspended[0]
		m.suspended = m.suspended[1:]
		m.current, m.since = resume, m.now()
		return resume, true
	}
	return "", false
}

// Stop drops a source entirely, whether it is playing or merely suspended. Used when
// the user switches COMMS off while an announcement is talking over it: the radio must
// not come back afterwards.
func (m *Mixer) Stop(src Source) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.current == src {
		m.current, m.since = "", time.Time{}
	}
	kept := m.suspended[:0]
	for _, s := range m.suspended {
		if s != src {
			kept = append(kept, s)
		}
	}
	m.suspended = kept
}

func (m *Mixer) Current() Source {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.current
}

func (m *Mixer) Suspended() []Source {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Source(nil), m.suspended...)
}

// --- the microphone -------------------------------------------------------------

// BirdNET listens continuously, but only when the radio is not playing: the user's call
// (2026-07-18), so the audio path stays sane and the detector does not spend the
// evening identifying Bayern 3 as a nightingale.
func BirdListeningAllowed(speaker Source) bool {
	return speaker != SourceRadio
}

// KnownSources is the priority table as a sorted list, for the status page.
func KnownSources() []Source {
	out := make([]Source, 0, len(priority))
	for s := range priority {
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool { return priority[out[i]] > priority[out[j]] })
	return out
}

package main

import (
	"testing"
	"time"
)

func newTestMixer() *Mixer { return NewMixer(fixedClock(time.Unix(0, 0))) }

func TestAnIdleSpeakerGrantsAnything(t *testing.T) {
	m := newTestMixer()
	if g := m.Claim(SourceRadio); !g.Granted {
		t.Fatalf("expected a grant, got %+v", g)
	}
	if m.Current() != SourceRadio {
		t.Errorf("radio should hold the speaker, got %q", m.Current())
	}
}

func TestAnAnnouncementInterruptsTheRadio(t *testing.T) {
	m := newTestMixer()
	m.Claim(SourceRadio)

	g := m.Claim(SourceAnnouncement)
	if !g.Granted || g.Preempted != SourceRadio {
		t.Fatalf("the announcement should preempt the radio, got %+v", g)
	}
}

// The behaviour that makes an interruption feel like an interruption rather than like
// the radio breaking.
func TestTheRadioResumesAfterAnAnnouncement(t *testing.T) {
	m := newTestMixer()
	m.Claim(SourceRadio)
	m.Claim(SourceAnnouncement)

	resume, ok := m.Release(SourceAnnouncement)
	if !ok || resume != SourceRadio {
		t.Fatalf("expected the radio to resume, got %q/%v", resume, ok)
	}
	if m.Current() != SourceRadio {
		t.Errorf("the radio should hold the speaker again, got %q", m.Current())
	}
}

func TestAnAnnouncementDoesNotResumeAfterBeingPreempted(t *testing.T) {
	m := newTestMixer()
	m.Claim(SourceAnnouncement)
	m.Claim(SourceAlarm)

	// A two-second announcement that got cut off by an alarm is stale by the time the
	// alarm is done; replaying it then would be confusing.
	if resume, ok := m.Release(SourceAlarm); ok {
		t.Fatalf("nothing should resume, got %q", resume)
	}
}

func TestTheAlarmOutranksEverything(t *testing.T) {
	for _, incumbent := range []Source{SourceRadio, SourceAnnouncement, SourceTalkdown} {
		m := newTestMixer()
		m.Claim(incumbent)
		if g := m.Claim(SourceAlarm); !g.Granted {
			t.Errorf("the alarm must preempt %s, got %+v", incumbent, g)
		}
	}
}

func TestALowerPriorityClaimIsRefused(t *testing.T) {
	m := newTestMixer()
	m.Claim(SourceAlarm)

	g := m.Claim(SourceRadio)
	if g.Granted {
		t.Fatal("the radio must not interrupt an alarm")
	}
	if g.Reason == "" {
		t.Error("a refusal should say who holds the speaker")
	}
}

// Equal priority means the incumbent keeps it: swapping one announcement for another
// mid-sentence is just noise.
func TestEqualPriorityLetsTheIncumbentFinish(t *testing.T) {
	m := newTestMixer()
	m.Claim(SourceAnnouncement)
	if g := m.Claim(SourceAnnouncement); !g.Granted {
		t.Error("re-claiming what you already hold should succeed quietly")
	}
	if len(m.Suspended()) != 0 {
		t.Error("nothing should have been suspended")
	}
}

func TestStoppingASuspendedSourceKeepsItFromComingBack(t *testing.T) {
	m := newTestMixer()
	m.Claim(SourceRadio)
	m.Claim(SourceAnnouncement)

	// The user switches COMMS off while the announcement is talking over it.
	m.Stop(SourceRadio)

	if resume, ok := m.Release(SourceAnnouncement); ok {
		t.Fatalf("a stopped radio must not resume, got %q", resume)
	}
	if m.Current() != "" {
		t.Errorf("the speaker should be idle, got %q", m.Current())
	}
}

func TestReleasingSomethingYouDoNotHoldIsANoOp(t *testing.T) {
	m := newTestMixer()
	m.Claim(SourceRadio)
	if _, ok := m.Release(SourceAlarm); ok {
		t.Error("releasing a source that is not playing should do nothing")
	}
	if m.Current() != SourceRadio {
		t.Errorf("the radio should still hold the speaker, got %q", m.Current())
	}
}

func TestAnUnknownSourceIsRefused(t *testing.T) {
	m := newTestMixer()
	if g := m.Claim(Source("kazoo")); g.Granted {
		t.Error("an unknown source must not get the speaker")
	}
}

// The microphone rule: BirdNET listens unless the radio is playing (user call).
func TestBirdListeningYieldsToTheRadio(t *testing.T) {
	if BirdListeningAllowed(SourceRadio) {
		t.Error("BirdNET must not listen while the radio plays")
	}
	for _, s := range []Source{"", SourceAnnouncement, SourceAlarm} {
		if !BirdListeningAllowed(s) {
			t.Errorf("BirdNET should listen while the speaker is %q", s)
		}
	}
}

func TestKnownSourcesAreOrderedByPriority(t *testing.T) {
	got := KnownSources()
	if got[0] != SourceAlarm {
		t.Errorf("the alarm should sort first, got %q", got[0])
	}
	if got[len(got)-1] != SourceRadio {
		t.Errorf("the radio should sort last, got %q", got[len(got)-1])
	}
}

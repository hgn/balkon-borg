package main

import (
	"encoding/json"
	"testing"
	"time"
)

func TestRingKeepsNewestFirstAndEvictsTheOldest(t *testing.T) {
	r := NewRing[int](3)
	for i := 1; i <= 5; i++ {
		r.Add(i)
	}
	got := r.Items()
	want := []int{5, 4, 3}
	if len(got) != len(want) {
		t.Fatalf("expected %d items, got %d", len(want), len(got))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("expected %v, got %v", want, got)
		}
	}
}

func TestRingItemsAreACopy(t *testing.T) {
	r := NewRing[int](3)
	r.Add(1)
	items := r.Items()
	items[0] = 99
	if r.Items()[0] != 1 {
		t.Error("mutating the returned slice must not touch the ring")
	}
}

func TestRingRejectsANonsenseCapacity(t *testing.T) {
	r := NewRing[int](0)
	for i := 0; i < DefaultRingSize+10; i++ {
		r.Add(i)
	}
	if r.Len() != DefaultRingSize {
		t.Errorf("expected the default cap %d, got %d", DefaultRingSize, r.Len())
	}
}

// --- coalescing -------------------------------------------------------------------

func TestCoalescerPublishesTheFirstChangeImmediately(t *testing.T) {
	now := time.Unix(1000, 0)
	c := NewCoalescer(time.Second, func() time.Time { return now })

	if c.Due() {
		t.Error("nothing changed yet, nothing to publish")
	}
	c.Touch()
	if !c.Due() {
		t.Error("a single event should show up immediately, not after the interval")
	}
}

func TestCoalescerHoldsBackABurst(t *testing.T) {
	now := time.Unix(1000, 0)
	c := NewCoalescer(5*time.Second, func() time.Time { return now })

	c.Touch()
	c.Due() // first publish

	// A feed at 1 Hz: without coalescing this would be a retained write per second,
	// forever, for data nobody reads between two app launches.
	for i := 0; i < 4; i++ {
		now = now.Add(time.Second)
		c.Touch()
		if c.Due() {
			t.Fatalf("published again after %ds, expected the 5s floor", i+1)
		}
	}

	now = now.Add(2 * time.Second)
	if !c.Due() {
		t.Error("once the floor has passed, the pending change should go out")
	}
}

func TestCoalescerStaysQuietWithoutChanges(t *testing.T) {
	now := time.Unix(1000, 0)
	c := NewCoalescer(time.Second, func() time.Time { return now })
	c.Touch()
	c.Due()

	now = now.Add(time.Hour)
	if c.Due() {
		t.Error("no change means no publish, however long it has been")
	}
}

// --- environment history ----------------------------------------------------------

func TestEnvHistoryCommitsOnCadence(t *testing.T) {
	now := time.Unix(10_000, 0)
	e := NewEnvHistory(24, time.Minute, func() time.Time { return now })

	e.Observe("t", 17.5)
	e.Observe("h", 62)
	e.Observe("p", 1013)

	if !e.Commit(true) {
		t.Fatal("the first sample should commit")
	}
	if e.Commit(true) {
		t.Error("a second commit within the interval should be refused")
	}

	now = now.Add(time.Minute)
	if !e.Commit(true) {
		t.Error("a commit after the interval should succeed")
	}
	if got := len(e.Samples()); got != 2 {
		t.Errorf("expected 2 samples, got %d", got)
	}
}

// Before the first NTP sync the Pi thinks it is 1970. A gap is obvious; wrong
// timestamps are not.
func TestEnvHistoryRefusesToStampAnUnsyncedClock(t *testing.T) {
	now := time.Unix(10_000, 0)
	e := NewEnvHistory(24, time.Minute, func() time.Time { return now })
	e.Observe("t", 17.5)

	if e.Commit(false) {
		t.Fatal("nothing may be persisted while the clock is untrusted")
	}
	if len(e.Samples()) != 0 {
		t.Error("no sample should have been stored")
	}
}

func TestEnvHistoryNeedsAReadingFirst(t *testing.T) {
	e := NewEnvHistory(24, time.Minute, fixedClock(time.Unix(10_000, 0)))
	// An absent ESP is normal: the feed stays empty rather than inventing zeros.
	if e.Commit(true) {
		t.Error("with no reading seen, there is nothing to commit")
	}
}

func TestEnvHistoryHoldsTheConfiguredWindow(t *testing.T) {
	now := time.Unix(0, 0)
	e := NewEnvHistory(1, time.Minute, func() time.Time { return now }) // 60 samples

	for i := 0; i < 100; i++ {
		e.Observe("t", float64(i))
		e.Commit(true)
		now = now.Add(time.Minute)
	}
	if got := len(e.Samples()); got != 60 {
		t.Errorf("expected an hour of minutes, got %d samples", got)
	}
}

// The chart reads left to right, so the payload is oldest first — the opposite of the
// SIGINT rings, on purpose.
func TestEnvPayloadIsOldestFirst(t *testing.T) {
	now := time.Unix(0, 0)
	e := NewEnvHistory(24, time.Minute, func() time.Time { return now })
	for i := 1; i <= 3; i++ {
		e.Observe("t", float64(i))
		e.Commit(true)
		now = now.Add(time.Minute)
	}

	data, err := json.Marshal(e.Payload())
	if err != nil {
		t.Fatal(err)
	}
	var got struct {
		V       int `json:"v"`
		Samples []struct {
			T float64 `json:"t"`
		} `json:"samples"`
	}
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got.V != SchemaVersion {
		t.Errorf("payload must carry the schema version, got %d", got.V)
	}
	if len(got.Samples) != 3 || got.Samples[0].T != 1 || got.Samples[2].T != 3 {
		t.Errorf("expected oldest first, got %+v", got.Samples)
	}
}

// --- events -----------------------------------------------------------------------

func TestEventRingKeepsTheLastTwenty(t *testing.T) {
	e := NewEvents(fixedClock(time.Unix(1000, 0)))
	for i := 0; i < 25; i++ {
		e.Add(CategoryBird, "amsel", true)
	}
	if got := len(e.Items()); got != EventRingSize {
		t.Errorf("expected %d events, got %d", EventRingSize, got)
	}
}

func TestEventsAreRefusedWhileTheClockIsUntrusted(t *testing.T) {
	e := NewEvents(fixedClock(time.Unix(1000, 0)))
	if e.Add(CategorySecurity, "person", false) {
		t.Fatal("an event with a 1970 timestamp would sort to the bottom forever")
	}
	if len(e.Items()) != 0 {
		t.Error("nothing should have been stored")
	}
}

func TestEventPayloadIsNewestFirst(t *testing.T) {
	e := NewEvents(fixedClock(time.Unix(1000, 0)))
	e.Add(CategoryBird, "first", true)
	e.Add(CategoryStorm, "second", true)

	data, err := json.Marshal(e.Payload())
	if err != nil {
		t.Fatal(err)
	}
	var got struct {
		Events []struct {
			Category string `json:"category"`
			Text     string `json:"text"`
		} `json:"events"`
	}
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if len(got.Events) != 2 || got.Events[0].Text != "second" {
		t.Fatalf("expected newest first, got %+v", got.Events)
	}
	if got.Events[0].Category != string(CategoryStorm) {
		t.Errorf("the category the app filters on must survive, got %q", got.Events[0].Category)
	}
}

// --- the ESP's plain-number topics -------------------------------------------------

// ESPHome publishes a bare number, not JSON, which is a shape the rest of the contract
// never uses. Worth pinning: a parser that silently drops these leaves the app with an
// empty chart and nothing to explain it.
func TestEnvTopicsMapToHistoryFields(t *testing.T) {
	for topic, field := range map[string]string{
		"balkon/env/temperature": "t",
		"balkon/env/humidity":    "h",
		"balkon/env/pressure":    "p",
	} {
		if envFields[topic] != field {
			t.Errorf("%s should feed %q, got %q", topic, field, envFields[topic])
		}
	}
	if _, ok := envFields[TopicEnvRecent]; ok {
		t.Error("env/recent is borgd's own snapshot, not a reading")
	}
}

package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func testPage(t *testing.T) string {
	t.Helper()
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	reg.Register("camera", okProbe, true)
	reg.Register("sdr", missingProbe, true)
	reg.ProbeAll()

	modes := NewModes(fixedClock(time.Unix(0, 0)))
	if _, err := modes.Apply(Comms, "fm", "bayern3"); err != nil {
		t.Fatal(err)
	}
	return StatusPage(reg, modes, "borg-pi", map[string]string{"build": "test"})
}

func TestStatusPageShowsEveryCapabilityAndMode(t *testing.T) {
	page := testPage(t)
	for _, want := range []string{"camera", "sdr", "nothing attached", "lumen", "comms",
		"fm", "bayern3", "borg-pi", "build"} {
		if !strings.Contains(page, want) {
			t.Errorf("the status page should mention %q", want)
		}
	}
}

func TestStatusPageLeadsWithWhatIsWrong(t *testing.T) {
	page := testPage(t)
	summary := strings.Index(page, "degraded or missing")
	table := strings.Index(page, "<h2>Capabilities")
	if summary < 0 {
		t.Fatal("the summary line should name the problem")
	}
	if summary > table {
		t.Error("the summary belongs above the tables, that is what you read first")
	}
}

// The page renders whatever a capability's reason says, and a reason can carry the
// output of a foreign tool. Escaping is not optional.
func TestStatusPageEscapesReasons(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	reg.Register("sdr", func() (State, string) {
		return StateDegraded, `<script>alert("x")</script>`
	}, true)
	reg.ProbeAll()

	page := StatusPage(reg, NewModes(fixedClock(time.Unix(0, 0))), "borg-pi", nil)

	if strings.Contains(page, "<script>") {
		t.Error("a reason must not be able to inject markup")
	}
	if !strings.Contains(page, "&lt;script&gt;") {
		t.Error("the reason should still be visible, escaped")
	}
}

func TestStatusPageIsSelfContained(t *testing.T) {
	page := testPage(t)
	// No build step, no framework, nothing to fetch: this page must render in five
	// years from a phone browser with no network beyond the Pi itself.
	for _, forbidden := range []string{"<script", "http://", "https://", "cdn"} {
		if strings.Contains(page, forbidden) {
			t.Errorf("the status page should not contain %q", forbidden)
		}
	}
}

func TestHealthJSONMatchesWhatThePageShows(t *testing.T) {
	reg := NewRegistry(fixedClock(time.Unix(0, 0)))
	reg.Register("sdr", missingProbe, true)
	reg.ProbeAll()
	modes := NewModes(fixedClock(time.Unix(0, 0)))
	if _, err := modes.Apply(Sentry, "armed", ""); err != nil {
		t.Fatal(err)
	}

	data, err := json.Marshal(BuildHealthJSON(reg, modes))
	if err != nil {
		t.Fatal(err)
	}

	var got struct {
		V            int    `json:"v"`
		State        string `json:"state"`
		Capabilities map[string]struct {
			State  string `json:"state"`
			Reason string `json:"reason"`
		} `json:"capabilities"`
		Modes map[string]struct {
			Submode string `json:"submode"`
		} `json:"modes"`
	}
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got.V != SchemaVersion {
		t.Errorf("payload must carry the schema version, got %d", got.V)
	}
	if got.State != string(StateMissing) {
		t.Errorf("aggregate should be missing, got %s", got.State)
	}
	if got.Capabilities["sdr"].Reason != "nothing attached" {
		t.Errorf("the reason should travel with the state, got %+v", got.Capabilities["sdr"])
	}
	if got.Modes["sentry"].Submode != "armed" {
		t.Errorf("sentry should be armed, got %+v", got.Modes["sentry"])
	}
}

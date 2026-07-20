package main

import (
	"encoding/json"
	"testing"
)

// The app parses these keys (models/health.dart) and the contract document names them.
// A rename here would show up as an app that displays nothing, with nothing in any log
// to explain it, so it gets a test rather than trust.
func TestCapabilityPayloadUsesTheContractKeys(t *testing.T) {
	data, err := json.Marshal(CapabilityPayload("degraded", "no data for 6m", "2026-07-20T21:00:00+02:00"))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"v", "state", "detail", "since"} {
		if _, ok := got[key]; !ok {
			t.Errorf("payload is missing the %q key the app reads", key)
		}
	}
	if _, ok := got["reason"]; ok {
		t.Error("`reason` is this code's internal name; the wire key is `detail`")
	}
	if got["v"] != float64(SchemaVersion) {
		t.Errorf("every payload carries the schema version, got %v", got["v"])
	}
}

func TestTopicsMatchTheContract(t *testing.T) {
	cases := map[string]string{
		ModeTopic(Lumen):     "balkon/mode/lumen",
		CmdModeTopic(Sentry): "balkon/cmd/mode/sentry",
		HealthTopic("sdr"):   "balkon/health/sdr",
		TopicModeFocus:       "balkon/mode/focus",
		TopicAdsbAircraft:    "balkon/adsb/aircraft",
		TopicIsmRecent:       "balkon/ism/recent",
		TopicTpmsRecent:      "balkon/tpms/recent",
	}
	for got, want := range cases {
		if got != want {
			t.Errorf("topic drift: got %q, want %q", got, want)
		}
	}
}

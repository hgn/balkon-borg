// The wire contract in code: topics and payload envelopes.
//
// src/shared/README.md is authoritative. This file mirrors it for the Pi the same way
// contract/topics.dart does for the app; when one changes, all three change in one
// commit. No logic beyond building the envelope, so it stays easy to diff against the
// document.
package main

import "time"

// SchemaVersion goes into every payload as "v" and is bumped on a breaking change.
const SchemaVersion = 1

// Mode is one of the four main modes, and also the path segment in its topics.
type Mode string

const (
	Lumen  Mode = "lumen"
	Comms  Mode = "comms"
	Sigint Mode = "sigint"
	Sentry Mode = "sentry"
)

// AllModes is the fixed order used wherever modes are listed.
var AllModes = []Mode{Lumen, Comms, Sigint, Sentry}

func ModeTopic(m Mode) string    { return "balkon/mode/" + string(m) }
func CmdModeTopic(m Mode) string { return "balkon/cmd/mode/" + string(m) }
func HealthTopic(cap string) string {
	return "balkon/health/" + cap
}

const (
	TopicModeFocus     = "balkon/mode/focus"
	TopicCmdFocus      = "balkon/cmd/focus"
	TopicCmdBrightness = "balkon/cmd/brightness"
	TopicCmdVolume     = "balkon/cmd/volume"
	TopicHealth        = "balkon/health"
	TopicEventRecent   = "balkon/event/recent"
	TopicEnvRecent     = "balkon/env/recent"
	TopicAdsbAircraft  = "balkon/adsb/aircraft"
	TopicIsmRecent     = "balkon/ism/recent"
	TopicTpmsRecent    = "balkon/tpms/recent"
	TopicKnob          = "balkon/state/knob"
)

// Subscriptions is everything borgd listens to: commands from clients and raw
// input from the ESP.
var Subscriptions = []string{
	"balkon/cmd/#",
	"balkon/input/#",
	"balkon/env/+",
	"balkon/presence",
}

// QoS 1 for state, commands and events (the contract's convention). Live telemetry
// that is republished a second later does not need the retransmit.
const (
	QoSState = 1
	QoSLive  = 0
)

// Timestamp is local time with offset, the contract's timestamp format.
func Timestamp(t time.Time) string { return t.Format(time.RFC3339) }

// Envelope wraps a payload the way the contract requires: schema version first.
func Envelope(fields map[string]any) map[string]any {
	out := map[string]any{"v": SchemaVersion}
	for k, v := range fields {
		out[k] = v
	}
	return out
}

// CapabilityPayload builds the balkon/health/<capability> message.
//
// The key is "detail", not "reason": that is what the contract says and what the app
// already parses. Built here rather than inline at the publish site so the naming is
// testable against the document instead of trusted.
func CapabilityPayload(state, detail, since string) map[string]any {
	return Envelope(map[string]any{"state": state, "detail": detail, "since": since})
}

// Borgd's own capability, set to missing by the last will so a dead borgd is
// visible rather than silently stale (contract: "borgd down" vs "all quiet").
const CapabilityBorgd = "borgd"

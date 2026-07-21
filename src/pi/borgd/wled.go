// The bridge to WLED.
//
// WLED runs its own firmware on its own controller and speaks its own MQTT API. The
// borgd is the only thing that talks to it (decision 2026-07-20: the ESP publishes
// inputs, the Pi owns the light), so every path that changes the light ends here:
// the app's brightness command, the panel's encoder, a LUMEN submode, the SENTRY
// alarm's flash.
//
// Payloads are WLED's, not ours. Keeping the translation in one file means the rest of
// borgd deals in submodes and percentages and never in preset numbers.
package main

import (
	"encoding/json"
	"fmt"
)

// WLEDTopic is the device topic configured in WLED itself. Its API topics hang below
// it, and it publishes its state on <topic>/v, which the app already reads for the
// ambient glow.
const WLEDTopic = "wled/balkon"

func WLEDAPITopic() string   { return WLEDTopic + "/api" }
func WLEDStateTopic() string { return WLEDTopic + "/v" }

// wledPresets maps LUMEN submodes onto WLED presets. The numbers live in WLED's own
// configuration; this is the one place that has to agree with it, and a submode with no
// preset falls back to a plain colour/effect payload rather than doing nothing.
var wledPresets = map[string]int{
	"ambient":       1,
	"full":          2,
	"cozy":          3,
	"distance-auto": 4,
	"info-ticker":   5,
	"disco":         6,
	"strobe":        7,
	"police":        8,
	"visualiser":    9,
}

// WLEDCommand is a payload for WLED's JSON API, kept as a map because WLED accepts a
// partial state and ignores what it does not know.
type WLEDCommand map[string]any

// WLEDForSubmode turns a LUMEN submode into a WLED command.
//
// Off is `{"on":false}` rather than brightness zero: a lamp at zero brightness is still
// on, still drawing current, and still reports itself as on to everything that asks.
func WLEDForSubmode(submode string, brightness int) (WLEDCommand, error) {
	if submode == Off {
		return WLEDCommand{"on": false}, nil
	}
	preset, ok := wledPresets[submode]
	if !ok {
		return nil, fmt.Errorf("no WLED preset for LUMEN submode %q", submode)
	}
	return WLEDCommand{"on": true, "bri": clamp(brightness, 1, 255), "ps": preset}, nil
}

// WLEDBrightness is the encoder and the app's slider. It does not switch the light on:
// turning the knob while the light is off should not surprise anybody with light.
func WLEDBrightness(value int) WLEDCommand {
	return WLEDCommand{"bri": clamp(value, 0, 255)}
}

// WLEDFlash is the SENTRY effector (U11) and the storm warning: a short, loud
// interruption that WLED plays on its own and then returns from, so a dropped
// "restore" message cannot leave the balcony strobing all night.
func WLEDFlash(seconds int, red bool) WLEDCommand {
	cmd := WLEDCommand{
		"on":  true,
		"bri": 255,
		"seg": []map[string]any{{"fx": 1, "sx": 220, "ix": 255}}, // blink, fast
		// WLED's own timer: it reverts to the previous state when it expires.
		"nl": map[string]any{"on": true, "dur": seconds / 60, "mode": 0},
	}
	if red {
		cmd["seg"] = []map[string]any{{
			"fx":  1,
			"sx":  220,
			"ix":  255,
			"col": [][]int{{255, 0, 0}, {0, 0, 0}},
		}}
	}
	return cmd
}

// WLEDArmedPulse is the SENTRY reminder while armed (U11, user call 2026-07-18): a
// short, dim red breath rather than the alarm's police light. Loud enough to catch the
// eye from the balcony door, quiet enough to live with for an evening.
//
// Like the flash it carries its own timer, so a lost message cannot leave the balcony
// glowing red: WLED reverts to whatever LUMEN was doing by itself.
func WLEDArmedPulse() WLEDCommand {
	return WLEDCommand{
		"on":  true,
		"bri": 40,
		"seg": []map[string]any{{
			"fx":  2, // breathe
			"sx":  60,
			"col": [][]int{{120, 0, 0}, {0, 0, 0}},
		}},
		"nl": map[string]any{"on": true, "dur": 1, "mode": 0},
	}
}

func (c WLEDCommand) Encode() ([]byte, error) { return json.Marshal(c) }

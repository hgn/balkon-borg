// The front panel's buttons and encoder (U2).
//
// The ESP publishes what happened; this decides what it means. Four buttons and one
// knob have to reach four main modes, their submodes, their channels and two continuous
// quantities, so the mapping is a small state machine rather than a pile of cases:
//
//	Button 1  short: cycle focus (which mode the panel steers)   long: unpin
//	Button 2  short: next submode within the focused mode        long: switch it off
//	Button 3  short: next channel, where the submode has a list
//	Button 4  reserve
//	Encoder   turn: adjust the current target                    push: light <-> audio
//
// Pure logic. It returns the commands to carry out; main.go performs them.
package main

import (
	"fmt"
	"sync"
)

// KnobTarget is what the encoder currently adjusts. Two continuous quantities and one
// knob, so the target is switchable rather than the knob being a redundant off switch.
type KnobTarget string

const (
	KnobLight KnobTarget = "light"
	KnobAudio KnobTarget = "audio"
)

// InputAction is what the panel reports.
type InputAction struct {
	Button int    // 1..4, 0 for encoder events
	Press  string // "short" or "long"
	Delta  int    // encoder detents, positive is clockwise
	Push   bool   // encoder push
}

// PanelEffect is what an input should cause. Exactly one field is set; the zero value
// means "nothing to do", which is a legitimate outcome (button 4 is a reserve).
type PanelEffect struct {
	Focus      *Mode       // switch focus
	Unpin      *Mode       // release a manual pin back to automatic
	SetSubmode *ModeChange // apply a submode/channel
	Brightness *int        // 0..255
	Volume     *int        // 0..100
	KnobTarget *KnobTarget // the target changed, publish it
}

type ModeChange struct {
	Mode    Mode
	Submode string
	Chan    string
}

// Panel holds what the buttons need to remember between presses: which mode they steer
// and what the knob is pointing at.
type Panel struct {
	mu         sync.Mutex
	focus      Mode
	knob       KnobTarget
	brightness int
	volume     int
	// step is how much one detent moves a continuous value. Brightness is 0..255 and
	// volume 0..100, so one step is a visible but not violent change in both.
	brightnessStep int
	volumeStep     int
}

func NewPanel() *Panel {
	return &Panel{
		focus:          Lumen,
		knob:           KnobLight,
		brightness:     128,
		volume:         40,
		brightnessStep: 16,
		volumeStep:     5,
	}
}

func (p *Panel) Focus() Mode      { p.mu.Lock(); defer p.mu.Unlock(); return p.focus }
func (p *Panel) Knob() KnobTarget { p.mu.Lock(); defer p.mu.Unlock(); return p.knob }
func (p *Panel) Brightness() int  { p.mu.Lock(); defer p.mu.Unlock(); return p.brightness }
func (p *Panel) Volume() int      { p.mu.Lock(); defer p.mu.Unlock(); return p.volume }
func (p *Panel) SetBrightness(v int) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.brightness = clamp(v, 0, 255)
}
func (p *Panel) SetVolume(v int) { p.mu.Lock(); defer p.mu.Unlock(); p.volume = clamp(v, 0, 100) }
func (p *Panel) SetFocus(m Mode) { p.mu.Lock(); defer p.mu.Unlock(); p.focus = m }

// Handle maps an input onto its effect, given the current mode states.
func (p *Panel) Handle(in InputAction, modes *Modes) PanelEffect {
	p.mu.Lock()
	defer p.mu.Unlock()

	switch {
	case in.Push:
		// Short push toggles what the knob adjusts; the panel briefly shows which.
		if p.knob == KnobLight {
			p.knob = KnobAudio
		} else {
			p.knob = KnobLight
		}
		target := p.knob
		return PanelEffect{KnobTarget: &target}

	case in.Delta != 0:
		if p.knob == KnobLight {
			p.brightness = clamp(p.brightness+in.Delta*p.brightnessStep, 0, 255)
			v := p.brightness
			return PanelEffect{Brightness: &v}
		}
		p.volume = clamp(p.volume+in.Delta*p.volumeStep, 0, 100)
		v := p.volume
		return PanelEffect{Volume: &v}

	case in.Button == 1:
		if in.Press == "long" {
			mode := p.focus
			return PanelEffect{Unpin: &mode}
		}
		p.focus = nextMode(p.focus)
		mode := p.focus
		return PanelEffect{Focus: &mode}

	case in.Button == 2:
		current := modes.Get(p.focus)
		if in.Press == "long" {
			// The quick way out: hold to switch the focused mode off, without
			// cycling through nine light programmes to reach "off".
			return PanelEffect{SetSubmode: &ModeChange{Mode: p.focus, Submode: Off}}
		}
		next := nextSubmode(p.focus, current.Submode)
		return PanelEffect{SetSubmode: &ModeChange{Mode: p.focus, Submode: next}}

	case in.Button == 3:
		current := modes.Get(p.focus)
		next, ok := nextChannel(p.focus, current.Submode, current.Chan)
		if !ok {
			return PanelEffect{} // inert where the submode has no list
		}
		return PanelEffect{SetSubmode: &ModeChange{
			Mode: p.focus, Submode: current.Submode, Chan: next}}
	}
	return PanelEffect{}
}

// nextMode cycles focus in the same order the app's grid shows.
func nextMode(current Mode) Mode {
	for i, m := range AllModes {
		if m == current {
			return AllModes[(i+1)%len(AllModes)]
		}
	}
	return AllModes[0]
}

// nextSubmode walks the mode's list, wrapping around. "off" is in the list on purpose:
// cycling past the end of the programmes lands on off, which is how a mode is switched
// off from the panel.
func nextSubmode(mode Mode, current string) string {
	list := Submodes[mode]
	for i, s := range list {
		if s == current {
			return list[(i+1)%len(list)]
		}
	}
	if len(list) > 1 {
		return list[1]
	}
	return Off
}

// Channels are the sub-submodes button 3 walks: stations, presets, filters. Empty for
// submodes that have no list, which makes the button inert there rather than surprising.
var Channels = map[Mode]map[string][]string{
	Comms: {
		"fm":      {"bayern3", "b5aktuell", "antenne", "rockantenne"},
		"dab":     {"deutschlandfunk", "br24", "egofm"},
		"airband": {"approach", "atis", "director", "tower"},
	},
	Sigint: {
		"adsb": {"all", "low", "special"},
	},
}

func nextChannel(mode Mode, submode, current string) (string, bool) {
	list := Channels[mode][submode]
	if len(list) == 0 {
		return "", false
	}
	for i, c := range list {
		if c == current {
			return list[(i+1)%len(list)], true
		}
	}
	return list[0], true
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// ParseInputTopic maps the ESP's input topics onto an action. Returns false for
// anything unrecognised, since the panel is a device that may be updated separately.
func ParseInputTopic(topic string, payload map[string]any) (InputAction, bool) {
	switch topic {
	case "balkon/input/button":
		id, ok := payload["id"].(float64)
		if !ok {
			return InputAction{}, false
		}
		action, _ := payload["action"].(string)
		if action != "short" && action != "long" {
			action = "short"
		}
		return InputAction{Button: int(id), Press: action}, true
	case "balkon/input/encoder":
		if action, ok := payload["action"].(string); ok && action == "push" {
			return InputAction{Push: true}, true
		}
		delta, ok := payload["delta"].(float64)
		if !ok || delta == 0 {
			return InputAction{}, false
		}
		return InputAction{Delta: int(delta)}, true
	}
	return InputAction{}, false
}

// KnobPayload is the retained `balkon/state/knob` message, so the app and the panel can
// both show what the encoder is pointing at.
func KnobPayload(target KnobTarget) map[string]any {
	return Envelope(map[string]any{"target": string(target)})
}

func (e PanelEffect) String() string {
	switch {
	case e.Focus != nil:
		return fmt.Sprintf("focus=%s", *e.Focus)
	case e.Unpin != nil:
		return fmt.Sprintf("unpin=%s", *e.Unpin)
	case e.SetSubmode != nil:
		return fmt.Sprintf("%s=%s/%s", e.SetSubmode.Mode, e.SetSubmode.Submode, e.SetSubmode.Chan)
	case e.Brightness != nil:
		return fmt.Sprintf("brightness=%d", *e.Brightness)
	case e.Volume != nil:
		return fmt.Sprintf("volume=%d", *e.Volume)
	case e.KnobTarget != nil:
		return fmt.Sprintf("knob=%s", *e.KnobTarget)
	}
	return "nothing"
}

package main

import (
	"encoding/json"
	"testing"
	"time"
)

func testModes() *Modes { return NewModes(fixedClock(time.Unix(1000, 0))) }

func TestButtonOneCyclesFocus(t *testing.T) {
	p, m := NewPanel(), testModes()

	seen := []Mode{}
	for i := 0; i < len(AllModes); i++ {
		effect := p.Handle(InputAction{Button: 1, Press: "short"}, m)
		if effect.Focus == nil {
			t.Fatalf("expected a focus change, got %s", effect)
		}
		seen = append(seen, *effect.Focus)
	}
	// A full round trip: four presses, four modes, back where it started.
	if seen[len(seen)-1] != Lumen {
		t.Errorf("expected to wrap back to lumen, got %v", seen)
	}
}

func TestButtonTwoWalksTheSubmodesOfTheFocusedMode(t *testing.T) {
	p, m := NewPanel(), testModes() // focus starts on lumen, everything off

	effect := p.Handle(InputAction{Button: 2, Press: "short"}, m)
	if effect.SetSubmode == nil || effect.SetSubmode.Mode != Lumen {
		t.Fatalf("expected a lumen submode change, got %s", effect)
	}
	if effect.SetSubmode.Submode != "ambient" {
		t.Errorf("expected the first programme after off, got %q", effect.SetSubmode.Submode)
	}
}

// Nine light programmes are a long way to press through when you just want it dark.
func TestHoldingButtonTwoSwitchesTheModeOff(t *testing.T) {
	p, m := NewPanel(), testModes()
	if _, err := m.Apply(Lumen, "disco", ""); err != nil {
		t.Fatal(err)
	}

	effect := p.Handle(InputAction{Button: 2, Press: "long"}, m)
	if effect.SetSubmode == nil || effect.SetSubmode.Submode != Off {
		t.Fatalf("expected off, got %s", effect)
	}
}

func TestButtonThreeWalksChannelsAndIsInertWithoutAList(t *testing.T) {
	p, m := NewPanel(), testModes()
	p.SetFocus(Comms)
	if _, err := m.Apply(Comms, "fm", "bayern3"); err != nil {
		t.Fatal(err)
	}

	effect := p.Handle(InputAction{Button: 3, Press: "short"}, m)
	if effect.SetSubmode == nil || effect.SetSubmode.Chan != "b5aktuell" {
		t.Fatalf("expected the next station, got %s", effect)
	}

	// Shortwave has no station list, so the button does nothing rather than something
	// surprising.
	if _, err := m.Apply(Comms, "shortwave", ""); err != nil {
		t.Fatal(err)
	}
	if effect := p.Handle(InputAction{Button: 3, Press: "short"}, m); effect.SetSubmode != nil {
		t.Errorf("expected an inert button, got %s", effect)
	}
}

func TestButtonFourIsReserved(t *testing.T) {
	p, m := NewPanel(), testModes()
	if effect := p.Handle(InputAction{Button: 4, Press: "short"}, m); effect.String() != "nothing" {
		t.Errorf("button 4 is a reserve, got %s", effect)
	}
}

// One knob, two continuous quantities: the push switches which one it drives.
func TestThePushTogglesTheKnobTarget(t *testing.T) {
	p, m := NewPanel(), testModes()
	if p.Knob() != KnobLight {
		t.Fatalf("expected the knob to start on the light, got %q", p.Knob())
	}

	effect := p.Handle(InputAction{Push: true}, m)
	if effect.KnobTarget == nil || *effect.KnobTarget != KnobAudio {
		t.Fatalf("expected the target to become audio, got %s", effect)
	}
	p.Handle(InputAction{Push: true}, m)
	if p.Knob() != KnobLight {
		t.Error("pushing again should come back to the light")
	}
}

func TestTurningAdjustsWhateverTheKnobPointsAt(t *testing.T) {
	p, m := NewPanel(), testModes()

	effect := p.Handle(InputAction{Delta: 2}, m)
	if effect.Brightness == nil {
		t.Fatalf("expected a brightness change, got %s", effect)
	}
	if *effect.Brightness <= 128 {
		t.Errorf("clockwise should raise it, got %d", *effect.Brightness)
	}

	p.Handle(InputAction{Push: true}, m)
	effect = p.Handle(InputAction{Delta: -3}, m)
	if effect.Volume == nil {
		t.Fatalf("expected a volume change, got %s", effect)
	}
}

func TestContinuousValuesStopAtTheirLimits(t *testing.T) {
	p, m := NewPanel(), testModes()

	for i := 0; i < 100; i++ {
		p.Handle(InputAction{Delta: 5}, m)
	}
	if got := p.Brightness(); got != 255 {
		t.Errorf("brightness should stop at 255, got %d", got)
	}
	for i := 0; i < 100; i++ {
		p.Handle(InputAction{Delta: -5}, m)
	}
	if got := p.Brightness(); got != 0 {
		t.Errorf("brightness should stop at 0, got %d", got)
	}
}

func TestParsingThePanelsTopics(t *testing.T) {
	button, ok := ParseInputTopic("balkon/input/button",
		map[string]any{"id": 2.0, "action": "long"})
	if !ok || button.Button != 2 || button.Press != "long" {
		t.Errorf("button not parsed: %+v ok=%v", button, ok)
	}

	turn, ok := ParseInputTopic("balkon/input/encoder", map[string]any{"delta": -2.0})
	if !ok || turn.Delta != -2 {
		t.Errorf("encoder turn not parsed: %+v ok=%v", turn, ok)
	}

	push, ok := ParseInputTopic("balkon/input/encoder", map[string]any{"action": "push"})
	if !ok || !push.Push {
		t.Errorf("encoder push not parsed: %+v ok=%v", push, ok)
	}

	// The panel is flashed separately from the Pi, so an unknown message is normal and
	// must not be taken for something else.
	if _, ok := ParseInputTopic("balkon/input/gesture", map[string]any{}); ok {
		t.Error("an unknown input topic should be refused")
	}
	if _, ok := ParseInputTopic("balkon/input/encoder", map[string]any{"delta": 0.0}); ok {
		t.Error("a zero delta is not an event")
	}
}

func TestKnobPayloadCarriesTheTarget(t *testing.T) {
	data, _ := json.Marshal(KnobPayload(KnobAudio))
	var got map[string]any
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got["target"] != "audio" || got["v"] != float64(SchemaVersion) {
		t.Errorf("unexpected payload: %s", data)
	}
}

// --- WLED ---------------------------------------------------------------------------

func TestSubmodesMapToWLEDPresets(t *testing.T) {
	cmd, err := WLEDForSubmode("cozy", 200)
	if err != nil {
		t.Fatal(err)
	}
	if cmd["ps"] != 3 || cmd["on"] != true || cmd["bri"] != 200 {
		t.Errorf("unexpected command: %+v", cmd)
	}
}

// Zero brightness is not off: the lamp still runs and still reports itself as on.
func TestOffIsOffAndNotZeroBrightness(t *testing.T) {
	cmd, err := WLEDForSubmode(Off, 200)
	if err != nil {
		t.Fatal(err)
	}
	if cmd["on"] != false {
		t.Errorf("expected the light to be switched off, got %+v", cmd)
	}
	if _, hasBrightness := cmd["bri"]; hasBrightness {
		t.Errorf("off should not carry a brightness, got %+v", cmd)
	}
}

func TestAnUnknownSubmodeIsAnErrorNotASilentNoOp(t *testing.T) {
	if _, err := WLEDForSubmode("lava-lamp", 128); err == nil {
		t.Error("an unmapped submode should be reported, not silently ignored")
	}
}

// Turning the knob while the light is off should not surprise anybody with light.
func TestBrightnessDoesNotSwitchTheLightOn(t *testing.T) {
	cmd := WLEDBrightness(100)
	if _, hasOn := cmd["on"]; hasOn {
		t.Errorf("a brightness command should not touch the on state, got %+v", cmd)
	}
}

func TestBrightnessIsClamped(t *testing.T) {
	if got := WLEDBrightness(9000)["bri"]; got != 255 {
		t.Errorf("expected 255, got %v", got)
	}
	if got := WLEDBrightness(-5)["bri"]; got != 0 {
		t.Errorf("expected 0, got %v", got)
	}
}

// The alarm uses WLED's own timer, so a lost "stop" message cannot leave the balcony
// strobing all night.
func TestTheFlashCarriesItsOwnTimeout(t *testing.T) {
	cmd := WLEDFlash(120, true)
	nl, ok := cmd["nl"].(map[string]any)
	if !ok || nl["on"] != true {
		t.Fatalf("expected a nightlight timer, got %+v", cmd)
	}
	if _, err := cmd.Encode(); err != nil {
		t.Fatalf("the command must encode: %v", err)
	}
}

// The armed reminder must stay distinguishable from the alarm: same device, very
// different message.
func TestTheArmedPulseIsDimmerThanTheAlarmFlash(t *testing.T) {
	pulse, alarm := WLEDArmedPulse(), WLEDFlash(5, true)
	if pulse["bri"].(int) >= alarm["bri"].(int) {
		t.Errorf("the reminder should be dimmer than the alarm: %v vs %v",
			pulse["bri"], alarm["bri"])
	}
	nl, ok := pulse["nl"].(map[string]any)
	if !ok || nl["on"] != true {
		t.Error("the reminder needs its own timer, or a lost message leaves it glowing")
	}
}

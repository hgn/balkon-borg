# src/esp — ESP32 front panel

ESPHome config for the ESP32-DevKitC on the carrier board. Reads the buttons, encoder,
LD2410B radar and BME280, and **publishes them as raw input** — it does not decide
anything.

The panel is deliberately dumb (decision 2026-07-20): borgd on the borg-pi owns
mode state, brightness, volume and the light. An earlier version drove WLED directly,
which contradicted the contract and would have given one lamp two owners. The one
local behaviour left is the button LEDs, driven from the retained mode topics so the
panel still shows the last known state while the Pi is off.

| Publishes | Payload |
|---|---|
| `balkon/input/button` | `{"v":1,"id":1..4,"action":"short"\|"long"}` |
| `balkon/input/encoder` | `{"v":1,"delta":±1}` or `{"v":1,"action":"push"}` |
| `balkon/presence` | `{"v":1,"present":bool,"distance_cm":n}` |
| `balkon/env/temperature` · `/humidity` · `/pressure` | plain numbers |

| Subscribes | For |
|---|---|
| `balkon/mode/lumen` · `/comms` · `/sentry` | button LEDs 1-3 |
| `balkon/state/knob` | LED 4: lit when the encoder drives the volume |

## Pin mapping

Follows `../../pcb/docs/board-spec.md`: buttons GPIO13/14/27/26, button LEDs
GPIO4/23/18/19, encoder A/B/SW GPIO32/33/25, radar UART GPIO16(RX)/17(TX),
I²C GPIO21(SDA)/22(SCL). The series resistors on the board are transparent to
ESPHome.

## Controls

| Element | Function |
|---|---|
| Button 1 | light on/off (WLED `T`) |
| Button 2 | scene "cozy" (WLED preset 1) |
| Button 3 | scene "party" (WLED preset 2) |
| Button 4 | presence automatic on/off (LED4 shows state) |
| Encoder turn | brightness +/- |
| Encoder push | light off |
| Radar | with automatic on: presence turns the light on, absence (after 2 min) off |
| LED1 | presence detected |

**Planned control map** — once the mode system exists (see
[`../log/decisions.md`](../log/decisions.md), 2026-07-16 entries, and `docs/use-cases.md`
U2). Not yet in this YAML; no mode list is defined yet:

The three mode levels sit on the first three buttons in order; Button 1 switches the
button **focus** (the subsystems keep running in parallel, it does not stop them):

| Element | Planned function |
|---|---|
| Button 1 | cycle main mode / focus (LUMEN / COMMS / SIGINT / SENTRY); long press → automatic |
| Button 2 | cycle submode within the focus, incl. an explicit **off** (LUMEN → off/scene…; COMMS → off/FM/DAB/airband) |
| Button 3 | cycle sub-submode (station / frequency / preset; inert if none) |
| Button 4 | reserve |
| Encoder turn | adjust the current target (brightness **or** volume) |
| Encoder push | toggle the target (light ↔ audio); panel shows which |

The old "scene cozy/party", "on/off" and "encoder push = off" button roles go away:
scenes become LUMEN submodes on Button 2, and the whole device is switched at the mains.

## Prerequisites

- **Mosquitto** on the borg-pi5 (the hub); credentials in `secrets.yaml`, user `esp`
  with the shared password from `../shared/borg.yaml`.
- **WLED** with MQTT enabled, device topic `wled/balkon`, and presets matching
  `borgd/wled.go`. The ESP no longer talks to it; borgd does.

## Build / flash

```
make check                             # YAML sanity check (via make)
cp secrets.yaml.example secrets.yaml   # and fill in
esphome run balkon-borg.yaml           # first time over USB, then OTA
```

**Important:** flash the DevKit **before** installing it (or pull it from the
socket); the USB port is hard to reach once the enclosure is assembled.

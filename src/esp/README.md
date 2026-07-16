# src/esp — ESP32 front panel

ESPHome config for the ESP32-DevKitC on the carrier board. Reads the buttons,
encoder, LD2410B radar and BME280, and controls the **WLED light directly over
MQTT**.

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

| Element | Planned function |
|---|---|
| Button 1 | on/off |
| Button 2 | cycle submode within the current main mode |
| Button 3 | cycle main mode (short) / release pin to automatic (long) |
| Button 4 | cycle sub-submode (station/frequency/preset within the submode; inert if none) |
| Encoder turn | adjust the current target (brightness **or** volume) |
| Encoder push | toggle the target (light ↔ audio); panel shows which |

The old "scene cozy/party" and "encoder push = off" roles go away: scenes become Licht
submodes on Button 2, and off is Button 1.

## Prerequisites

- **WLED** with MQTT enabled, device topic `wled/balkon` (else adjust
  `substitutions.wled_topic`). Create presets 1/2 in WLED.
- **Mosquitto** on the borg-pi5 (the hub); credentials in `secrets.yaml`.

## Build / flash

```
make check                             # YAML sanity check (via make)
cp secrets.yaml.example secrets.yaml   # and fill in
esphome run balkon-borg.yaml           # first time over USB, then OTA
```

**Important:** flash the DevKit **before** installing it (or pull it from the
socket); the USB port is hard to reach once the enclosure is assembled.

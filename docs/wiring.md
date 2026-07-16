# Wiring and connector plan

Terminal assignment for the ESP32 carrier board and the 5 V distribution, plus the
**connector placement** (was open point README §8.1). This layout is **applied** in
`pcb/place-board.py` and the board is routed and DRC-clean against it.

## Board orientation in the enclosure

The carrier (150 × 92) hangs on the rear inner wall in the right-hand bay, centred at
enclosure (x = +105, z = 55), component side facing the open front (+Y). It sits on
8 mm bosses, ~100 mm clear to the LED panel, so component height is uncritical.

Fix the orientation so the KiCad axes map like this (long edge horizontal, it has to —
150 mm does not fit in the 110 mm height):

| KiCad board axis | Enclosure axis | Rationale |
|---|---|---|
| X 0 → 150 | enclosure x 30 → 180 | long edge horizontal; x=150 edge points at the +X end wall |
| Y 0 → 92  | enclosure z 9 → 101 (y=0 edge **down**, toward the floor) | radar tower + BME sit on the floor |

## Cable targets (post-mirror enclosure coordinates)

| From board | To | Where it is |
|---|---|---|
| `J_PWR`   | 5 V feed (Wago from the PSU) | cable gland, rear/end wall |
| `J_RADAR` | LD2410B in the LED tower | floor, x≈155 (under the board area), points forward |
| `J_BME`   | BME280 ambient opening | floor, x≈205 (right, outboard of the board) |
| `J_ENC`   | rotary encoder | **+X end wall**, y 56–92, z≈91 |
| `J_BTN1..4` | 4 illuminated buttons | **+X end wall**, 2×2 at y (56,92) × z (29,61) |

## Connector placement (applied)

- **Down edge (KiCad y≈8, the enclosure floor side):** `J_PWR` + `F1`, then `J_RADAR`
  and `J_BME`. Radar and BME cables drop straight to the tower/floor; the 5 V feed
  enters low near the gland.
- **Right short edge (KiCad x≈132, nearest the +X end wall):** `J_ENC` + `J_BTN1..4`,
  stacked, each button's NPN driver just inboard. The five cables run straight sideways
  to the end wall instead of looping around.
- ESP headers sit left of centre; decoupling by the 3V3 pin; the 15 series/driver
  resistors in three rows in the free band below the ESP.

The JST connectors are vertical (cable exits +Z, toward the open front), so placement
(not rotation) sets the cable length; each group sits nearest its target edge.

**Assumption to confirm:** the 5 V cable gland location. If it enters on the +X end wall
(next to the buttons) rather than the rear/floor, move `J_PWR` to the right edge with the
button group.

## Terminal assignment (ESP32-DevKitC-V4)

Authoritative pin map is in [`../pcb/docs/board-spec.md`](../pcb/docs/board-spec.md);
firmware in [`../src/esp/balkon-borg.yaml`](../src/esp/balkon-borg.yaml).
Summary:

| Net | GPIO | Function |
|---|---|---|
| `RADAR_TX/RX` | 16/17 (UART2) | LD2410B presence (220 Ω series) |
| `I2C_SDA/SCL` | 21/22 | BME280 (4.7 kΩ pull-ups DNP; breakout carries them) |
| `ENC_A/B/SW`  | 32/33/25 | rotary encoder (100 Ω, internal pull-ups) |
| `BTN1..4_SW`  | 13/14/27/26 | button switches (100 Ω, internal pull-ups) |
| `BTN1..4_LED` | 4/23/18/19 | NPN base (1 kΩ) → 5 V ring LED low-side |

## 5 V distribution

See [`power-distribution.md`](power-distribution.md) for the star + branch fuses. In
short: one 5 V feed from the LRS-150F-5 (trimmed 5.15 V), Wago-split into fused branches
(10 A LED / 5 A Pi / 2 A small electronics), common GND. `J_PWR` is on the 2 A branch
behind the board's F1 polyfuse.

# Wiring and connector plan

Terminal assignment for the ESP32 carrier board and the 5 V distribution, plus the
**connector placement plan** (open point in README §8.1). The board itself is done and
routed; this file decides where the JST connectors should sit so the cables reach their
targets cleanly. Nothing here is applied to `pcb/place-board.py` yet — it is the plan to
execute when the connector positions are frozen for the next board revision.

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

## Connector placement plan

The routed board currently groups `J_PWR/J_RADAR/J_BME` on one long edge and
`J_ENC/J_BTN` on the other. That works, but two groups then face away from their
targets. Recommended placement for the next revision:

- **Down edge (KiCad y=0, becomes the enclosure floor side):** `J_RADAR`, `J_BME`,
  `J_PWR`. Radar and BME cables drop straight down to the tower/floor; the 5 V feed
  enters low near the gland. Short, no crossing over the board face.
- **Right short edge (KiCad x=150, nearest the +X end wall):** `J_ENC` + `J_BTN1..4`.
  The five button/encoder cables then run straight sideways to the end wall instead of
  looping around from a long edge. 92 mm of edge holds five JST-XH 4-pin easily.
- Keep the JST entry direction pointing **off the board** (connectors on the very edge,
  latch outward) so a plugged cable does not sit over the DevKit or the resistors.

**Assumption to confirm:** the 5 V cable gland location. If it enters on the +X end wall
(next to the buttons) rather than the rear, move `J_PWR` to the right short edge with the
button group instead of the down edge.

## Terminal assignment (ESP32-DevKitC-V4)

Authoritative pin map is in [`../pcb/docs/board-spec.md`](../pcb/docs/board-spec.md);
firmware in [`../firmware/esphome/balkon-borg.yaml`](../firmware/esphome/balkon-borg.yaml).
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

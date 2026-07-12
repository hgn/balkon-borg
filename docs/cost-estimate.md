# Cost estimate

Rough bill of materials for building one unit, buying everything new (incl. the
dedicated Pi) and having the carrier PCB fabricated + the enclosure SLS-printed.
Prices are ballpark 2026, EU sourcing, in EUR. The enclosure print and whether the
Pi/camera are bought new are the big swing items.

## Bill of materials

| Area | Items | ~€ |
|---|---|---|
| **Compute** | Pi 5 (8 GB) 80, Active Cooler 6, microSD 64 GB 10 | **96** |
| **Light** | Athom WLED High-Power 18, SK6812 RGBW panel 344 px 35, opal diffuser 10, aluminium backing plate 10 | **73** |
| **ESP / sensing / controls** | ESP32-DevKitC 9, LD2410B 4, BME280 (genuine Bosch) 8, 4× illuminated buttons 16, EC11 encoder 3, 4× indicator LEDs 8 | **48** |
| **Reception + audio** | RTL-SDR V3 32, USB microphone 10, antenna + RG316 pigtail 13, USB speaker 8 | **63** |
| **Power** | Mean Well LRS-150-5 28, XT60 3, 2× Wago 221 3, fuses + holders 5, wire/ferrules 8 | **47** |
| **Carrier PCB** | Aisler fab (3 pcs) 40, THT parts (R/C/Q/JST/sockets/polyfuse) 15 | **55** |
| **Enclosure** | SLS/PA12 black, 2 halves (~822 cm³, 508×151×140 bounding box) | **150–250** |
| **Small parts** | heat-set inserts, screws M2.5/M3/M5, dowels, panel nuts, thermal pad, glue, insect mesh, zip ties | **25** |

**Total ≈ 550–750 €, realistically ~600–650 € mid.**

## Cost drivers

- **Enclosure SLS** is the largest single item and the biggest unknown: ~100 € at
  JLC3DP (China) vs. ~250–300 € at a German service. The 51 cm length drives it. Pull a
  real instant quote (JLC3DP / Craftcloud) before trusting a number — the STL is
  `docs/img/enclosure.stl` / `cad/build/*.step`.
- **borg-pi5** (~96 € with cooler + SD) is the second chunk. The older README budget
  (~455 €) excluded the dedicated Pi and assumed cheap FDM printing; SLS + Pi are the
  uplift.

## Not included

- **Camera Module 3** (~25 € if bought new) — listed as already on hand.
- **nas-Pi5** — a separate, pre-existing always-on Pi (remote access + occasional image storage).
- Tools, shipping, and the external 230 V wiring to the socket.

See [`enclosure-sintering.md`](enclosure-sintering.md) for print providers,
[`board-spec.md`](../pcb/docs/board-spec.md) for the PCB BOM, and
[`power-distribution.md`](power-distribution.md) for the power parts.

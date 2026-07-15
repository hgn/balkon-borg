# Cost estimate

Rough bill of materials for building one unit, buying everything new (incl. the
dedicated Pi) and having the carrier PCB fabricated + the enclosure SLS-printed.
Prices are ballpark 2026, EU sourcing, in EUR. The enclosure print and whether the
Pi/camera are bought new are the big swing items.

## Bill of materials

| Area | Items | ~€ |
|---|---|---|
| **Compute** | Pi 5 (8 GB) 80, Active Cooler 6, microSD 64 GB 10 | **96** |
| **Light** | Athom WLED High-Power 18, SK6812 RGBWW strip 5 m/60 per m (builds the 8×25 field) 32, opal diffuser NP40 443×93 (ordered 2026-07-15, 15.60 landed, actual) 16, alu plate 438×88×3 cut to size at Alufritze (ordered 2026-07-15, 42.82 incl. project fee + shipping, actual) 43 | **109** |
| **ESP / sensing / controls** | ESP32-DevKitC 9, LD2410B 4, BME280 (genuine Bosch) 8, 4× illuminated buttons 16, EC11 encoder 3, 4× indicator LEDs 8 | **48** |
| **Reception + audio** | RTL-SDR V4 32, USB microphone 10, antenna + RG316 pigtail 13, USB sound card (DELOCK 61645) 6, class-D amp (PAM8403) 3, Visaton BF 45 speaker 16 | **80** |
| **Power** | Mean Well LRS-150-5 28, XT60 3, 2× Wago 221 3, fuses + holders 5, wire/ferrules 8 | **47** |
| **Camera** | Raspberry Pi Camera Module 3 (standard), Amazon 2026-07-15, actual | **30** |
| **Carrier PCB** | Aisler Beautiful Boards (3 pcs, incl. VAT) **47**, THT parts (R/C/Q/JST/sockets/polyfuse) 15 | **62** |
| **Enclosure** | SLS/PA12 black, **two halves** at JLC3DP (re-order 2026-07-15 with the reviewed geometry): goods 208 $ + shipping 88 $ = 296 $ (~275 €), landed with German import VAT + duty | **350–365** |
| **Small parts** | heat-set inserts, screws M2.5/M3/M5, dowel pins, panel nuts, thermal pad, glue, insect mesh, zip ties | **25** |

**Total ≈ 845–860 €, realistically ~850 € mid** (PCB, enclosure, camera, diffuser and
alu plate are ordered actuals, not estimates; the one-off cut services carry project
fees and shipping that the early ballpark missed).

## Cost drivers

- **Enclosure SLS** is the largest single item. It is **split into two halves** (each
  ~254 mm) so it fits a standard SLS bed. Ordered at JLC3DP in **3201PA-F black**:
  the effective order is the **2026-07-15 re-order W2026071604138082** with the reviewed
  geometry (left 97.80 $, right 109.90 $, goods 207.70 $ plus 88.31 $ shipping =
  **296.01 $ order total**, ~275 € at ~1.08 $/€); it supersedes the cancelled 2026-07-14
  order (280.35 $, old down-camera geometry). Landed cost is higher again, because the
  shipment is over the 150 € threshold: German import VAT (19 %) and a small plastics
  duty (~6.5 %) are collected by the carrier on delivery, plus a handling fee, so budget
  **~350–365 € landed**. The steep part is shipping (88 $), not the print. A one-piece
  508 mm print would have needed a large-bed EU house (Sculpteo / Xometry / Materialise)
  at ~700–1000 €, so the split still saves a lot. Files:
  `cad/build/balkon-borg-left.step` / `-right.step`.
- **Carrier PCB** came in at **47.17 € for 3 boards** (Aisler Beautiful Boards, 2-layer,
  1.6 mm, HASL lead-free, 35 µm, incl. 19 % VAT). Only one board is populated; the other
  two are spares. THT parts (~15 €) and the ESP32-DevKitC (~9 €) are bought separately.
- **borg-pi5** (~96 € with cooler + SD) is the next chunk. The older README budget
  (~455 €) excluded the dedicated Pi and assumed cheap FDM printing; SLS + Pi are the
  uplift.

## Not included

- **nas-Pi5** — a separate, pre-existing always-on Pi (remote access + occasional image storage).
- Tools, shipping, and the external 230 V wiring to the socket.

See [`enclosure-sintering.md`](enclosure-sintering.md) for print providers,
[`board-spec.md`](../pcb/docs/board-spec.md) for the PCB BOM, and
[`power-distribution.md`](power-distribution.md) for the power parts.

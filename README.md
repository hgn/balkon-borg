# Balkon-Borg — project overview

*A smart, partly self-built **sensor-and-effector "borg"** under the balcony, tied into the
home network and the Raspberry Pi home server.*

It **senses** the terrace from many sources and **acts** on it:

- **Inputs (senses):** presence/motion **radar** (LD2410B, pointing forward), **acoustics**
  via a USB **microphone** (bird calls → BirdNET), **environment** (BME280:
  temperature, humidity, pressure), a **camera** (person/animal detection with Frigate),
  and **radio** via an RTL-SDR (aircraft/ADS-B, optional LoRa), plus **manual** input
  (four illuminated buttons + a rotary encoder).
- **Outputs (acts):** **light** — a WLED RGBW panel from cosy dinner glow to party effects;
  **sound** — a small USB speaker that plays a clip or says hello when something is
  detected; and the **home network / nas-Pi** — every event, reading and control flows
  over MQTT to dashboards, storage and remote access.

Everything runs on the enclosure's own **borg-pi5** (the hub) plus a low-solder ESP32
front panel, off one shared 5 V feed.

---

## Preview

Enclosure (SLS/PA12, rounded edges, ceiling-mount ears, slogans embossed) and the
ESP32 sensor carrier board (fully placed and routed). **Click the enclosure image to
open the STL in GitHub's interactive 3D viewer** (`docs/img/enclosure.stl`, exported
by `make render`):

[![Enclosure](docs/img/enclosure.png)](docs/img/enclosure.stl)

![Carrier board](docs/img/pcb-top.png)

---

## Documentation

- **Start here:** [decision log](log/decisions.md) (why the build is the way it is) ·
  [design review](docs/design-review.md) (open issues, ranked) ·
  [cost estimate](docs/cost-estimate.md)
- **Build & hardware:** [network](docs/network.md) (who is on when, MQTT flow + sequence) ·
  [light scenarios](docs/light-scenarios.md) ·
  [enclosure & SLS printing](docs/enclosure-sintering.md) ·
  [build/integration notes](docs/build-notes.md) ·
  [power distribution](docs/power-distribution.md) ·
  [carrier board spec](pcb/docs/board-spec.md)
- **Domains:** [`cad/`](cad/README.md) (enclosure) ·
  [`pcb/`](pcb/README.md) (carrier board) ·
  [`firmware/esphome/`](firmware/esphome/README.md) (ESP32)

---

## 1 · Short description

A compact enclosure, screwed under the balcony (above the terrace, ~2 m from the
dining table), bundling several functions: mood-to-party lighting, presence and
environment sensing, aircraft reception (ADS-B) and bird-call recognition. Everything
runs off a shared 5 V feed and an MQTT/WiFi bus. The goal is a build that looks
*intentional* (one box, one light field, minimal cabling) rather than tinkered.

## 2 · Goals

- **One visible box, minimal cabling** — exactly one 230 V feed, everything else 5 V + radio.
- **Value over gimmick** — automations and data actually used day to day (light at the table, weather, birds, aircraft).
- **Cleanly integrated into the existing setup** — MQTT bus, Podman/Quadlets, Netdata/Grafana.
- **Maintainable and extensible** — low-solder, pre-flashed components; enclosure as parametric code (CadQuery), not a throwaway click model.
- **Robust continuous outdoor operation** (protected) — thermally and electrically designed for summer duty.

## 3 · Use cases

| # | Use case | Realisation |
|---|---|---|
| U1 | Light at the dining table, automatic in the evening | SK6812 RGBW panel (WLED) + LD2410B radar → soft fade-in on presence, warm-white channel |
| U2 | Manual light control without a phone | 4× stainless buttons + rotary encoder (on/off, scenes, dimming, automation pause) |
| U3 | Effect / party light | WLED 2D effects, strobe, scrolling text on the 8×43 matrix |
| U4 | Environment data | BME280 (temperature/humidity/pressure) → MQTT → dashboard |
| U5 | Aircraft reception | RTL-SDR V3 + readsb/tar1090 (approach MUC, optional feed) |
| U6 | Bird-call log | USB microphone → BirdNET → species statistics over the season |
| U7 | Camera + local recognition | Camera Module 3 → Frigate (people/animals) **on the Pi 5 CPU** |
| U8 | Passive radio listening (optional) | LoRa/Meshtastic **RX** over the SDR (no active transmit node) |
| U9 | Audio feedback | small **USB speaker** on the borg-pi5 → plays a short clip / says hello when something is detected |

## 4 · System components (current state)

- **Central compute (borg-pi5):** Raspberry Pi 5 (8 GB) + Active Cooler, microSD in the enclosure — **the hub the project is about**: recording (camera/audio/SDR), local inference (Frigate, readsb/tar1090, BirdNET-Go), and the **MQTT broker (Mosquitto), dashboards and app**. Powered on **only when needed**, not 24/7.
- **Sensor/control front panel:** ESP32 (ESPHome) with LD2410B (UART), BME280 (I²C), 4 buttons + encoder (GPIO).
- **Light:** Athom high-power WLED controller + SK6812 RGBW-WW compact panel (8 rows × 43 = 344 px) on a 3 mm aluminium plate, opal acrylic diffuser.
- **Reception:** RTL-SDR V3 (ADS-B 1090 MHz, optional LoRa RX), USB microphone (on the Pi 5). The LD2410B radar points **forward** (in the LED tower), toward the terrace.
- **Audio out:** a small **USB speaker** (or a cheap USB soundcard + mini speaker) on the borg-pi5 — plays a short wav on events (detection, greeting).
- **Power:** Mean Well LRS-150F-5 (5 V/22 A) in its own V-0 enclosure, fused branches.
- **Enclosure:** 3D print in SLS/PA12 (black), 2 parts (build-volume split with dowel pins); aluminium plate = front + heatsink.
- **nas-Pi5 (existing, minor role):** a separate, **always-on** Raspberry Pi 5 wired to the Fritz!Box. Only the **remote-access point** (reach the unit from outside) and occasional **image/data storage** — not the hub (see [network](docs/network.md)).

## 5 · Architecture and data flow

The **borg-pi5** is the hub: it captures camera (CSI), audio (USB) and RF (USB SDR), runs
the object recognition locally, and hosts the **MQTT broker, dashboards and app** — only
events and metadata go on over MQTT, no continuous raw stream. The **ESP32** handles the
human-facing, real-time-critical I/O (buttons, encoder, radar) and the slow environment
sensors; it is deliberately the *cheap, replaceable front panel*. The **nas-Pi5** is only
a minor, always-on helper (remote access + occasional image storage); the borg-pi5 runs
when needed, so its light/MQTT automation is available while it is on. Path: borg-pi5 →
WiFi repeater → cable → Fritz!Box → nas-Pi5 (see [network](docs/network.md)).

## 6 · Constraints

**Environment**
- Mounting location on the balcony underside: **rain-protected**, but raised humidity possible; Munich **summer heat** is relevant.
- No true IP65 needed (protected location) → **ventilated** enclosure with slits facing down + insect protection.

**Electrical**
- Exactly **one 230 V feed** (terrace socket, RCD-protected); target picture "no thousand cables".
- One shared **5 V PSU**, fused branches (10 A LED / 5 A Pi / 2 A small electronics), common GND, trimmer to **5.15 V**.
- **Fire safety:** the 230 V PSU **separated** from the printed part (its own V-0/metal enclosure); the printed part carries low voltage only.

**Thermal**
- **Aluminium plate = heatsink** of the LED layer, thermal contact to the enclosure (thermal pad at the supports).
- Pi 5 continuous load (now incl. **CPU object recognition**) → Active Cooler + ventilation are critical, not optional.
- WLED **Automatic Brightness Limiter** at ~8 A → caps the panel's heat and current.

**Mechanical / manufacturing**
- **3D print in SLS/PA12**, black-dyed (no supports, no layer lines, production look). See `docs/enclosure-sintering.md`.
- Parts larger than the build volume → **split** (X=0) with 4 mm dowel pins; STEP to the print service (German first: PRINCORE / Reents3D / 3D-Druckdienstleister.de).
- Radar sees through a **2 mm membrane**; camera/mic cut-outs integrated.

**Network**
- WiFi + MQTT as the bus; **Ethernet optional** (only makes the video stream more bulletproof).

**Skill level / preferences**
- Soldering and programming available, **not a full tinkerer** → solder-free/pre-flashed parts preferred (Athom pre-flashed, pluggable LED connectors, buttons with a pigtail).
- **Quality over price** — reflected in RGBW-WW (real warm white), stainless buttons, SLS.

**Budget**
- **~415 €** new parts + **~40 €** odds and ends (connectors, fuses, Wago, wire, screws, inserts, glands). Camera and NAS-Pi already on hand.

## 7 · Deliberately out of scope (with consequence)

| Dropped | Consequence |
|---|---|
| **E-ink status display** | Data shown only via the existing dashboards (Grafana/tar1090). |
| **AI HAT / Hailo NPU** | Object recognition runs on the **Pi 5 CPU** (one camera stream ok, lower FPS); **retrofittable** any time, the PCIe port stays free (optional NVMe SSD). |
| **Heltec / active Meshtastic node** | LoRa **receive** only over the SDR, no transmit into the mesh. |
| **AS3935 lightning sensor** | No local thunderstorm early warning. |
| **Stairville Wild Wash + USB-DMX** | No separate blinder; effect/strobe light comes from the WLED panel itself. |

## 8 · Open points / next steps

1. **Terminal assignment** — concrete ESP32 GPIOs, I²C addresses (BME280), Wago plan of the 5 V distribution.
2. **Podman quadlets** — Mosquitto, Frigate (CPU detector), readsb/tar1090, BirdNET-Go.
3. **Real board measurement** → adjust the mounting-boss positions in `balkon_borg.py` (CadQuery).
4. **WLED config** — 2D 43×8 serpentine, ABL at 8 A, presets/scenes + button mapping.
5. **PSU** — EEPROM `PSU_MAX_CURRENT=5000`, trim the output to 5.15 V.
6. **Fit test** — print a corner/brow (insert and diffuser-rebate fit) before the big halves.

## 9 · Key risks

- **Thermal in summer** — CPU detection raises the continuous load; ventilation and the Active Cooler decide stability.
- **Recognition performance** — without an NPU, FPS/stream limited; possibly a lighter model or a later Hailo retrofit.
- **Humidity/condensation** — mind the downward ventilation and possibly pressure equalisation so nothing collects.

## 10 · Built with Claude (Opus / Fable)

The complete hardware design in this repo — the parametric CadQuery enclosure, the
SKiDL → KiCad → Freerouting carrier board, the ESPHome firmware, the MQTT/Podman
plumbing and the docs — was generated in collaboration with Anthropic's **Claude**
(Opus 4.x and **Fable 5**), driving the CAD, PCB, render and review tooling directly.
For the curious, a `/context` snapshot from one of the working sessions:

```text
Context Usage
⛁ ⛁ ⛁ ⛁ ⛀ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁   Fable 5
⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁   claude-fable-5
⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁ ⛁   323k/1m tokens (32%)
⛁ ⛁ ⛁ ⛁ ⛁ ⛀ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   Estimated usage by category
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ System prompt:  3.9k tokens (0.4%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ System tools:   8.8k tokens (0.9%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Memory files:   5.6k tokens (0.6%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Skills:         2.6k tokens (0.3%)
⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶ ⛶   ⛁ Messages:     302.8k tokens (30.3%)
                                        ⛶ Free space:   676.4k (67.6%)

MCP tools · 25 tools · loaded on-demand
Memory files · 3 files · 5.6k tokens
Skills · 21 skills · 2.6k tokens
```

The bulk (the "Messages" slice) is the working transcript: CAD builds and OpenCascade
booleans, KiCad/pcbnew scripting, Freerouting runs, DRC reports and render round-trips.

### Who did what

The honest split: **the author has no background in hardware design, electronics,
schematics or PCB layout** — this project would simply not exist without Claude. The
human side was defining the **use cases and requirements** and stepping in only where
it was unavoidable (a few KiCad steps). The actual engineering — the parametric
enclosure, the schematic and board, the routing, the firmware, the DfAM and signal-flow
reviews — was done by **Claude (mainly Fable 5, with Opus 4.8)**.

### Token usage and cost

Measured with [`ccusage`](https://github.com/ryoppippi/ccusage) over three working days
(10–12 Jul 2026, Opus 4.8):

| Day | Input | Output | Cache write | Cache read | Total tokens | Cost |
|---|--:|--:|--:|--:|--:|--:|
| 2026-07-10 | 9,200 | 625,879 | 2,536,382 | 103,796,715 | 106,968,176 | $92.96 |
| 2026-07-11 | 28,183 | 671,930 | 2,860,378 | 203,925,544 | 207,486,035 | $147.51 |
| 2026-07-12 | 21,093 | 560,556 | 5,245,511 | 188,015,314 | 193,842,474 | $160.58 |
| **Total** | **58,476** | **1,858,365** | **10,642,271** | **495,737,573** | **≈508 M** | **$401.05** |

So a complete, fabrication-ready hardware package — SLS enclosure, routed carrier board,
firmware and docs — for **about $401** (≈370 €) of model usage. Roughly half a billion
tokens, most of it cache reads (re-reading the growing repo and transcript each turn),
which is why the token count is huge but the cost is not.

For scale: a freelance hardware developer taking on the same scope (enclosure CAD,
schematic + board layout + routing, firmware, and the write-up) would realistically
spend a few weeks — in the low-to-mid **five figures in euros**. The point is not that
Claude is "cheaper by X"; it is that a person with zero hardware background got to a
buildable design at all.


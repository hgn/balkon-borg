# CLAUDE.md — Balkon-Borg

Project-specific working context. Complements the global conventions in
`~/.claude/CLAUDE.md` (language, filenames with `-`, Make standard targets, Python
and C style, Git conventions). On conflict the global rules win, unless this file
deliberately deviates.

## Always read first

1. This file.
2. `log/decisions.md` — the decision log. Holds *why* the build is the way it is.
   Before re-opening a design question, check whether it is already settled there.
3. `README.md` when you need the full project overview (use cases U1-U8, components,
   constraints, scope boundaries).

## What this is

A hardware-plus-software hobby project: a multifunction unit under the balcony. One
enclosure bundles light (WLED panel), presence/environment sensing (ESP32), reception
(RTL-SDR, microphone) and a camera, tied over WiFi/MQTT to a NAS-Pi. Details in
`README.md`.

There are three compute nodes with a clear role split:
- **Edge Pi 5** — recording (camera/audio/SDR) and local inference (Frigate, readsb,
  BirdNET). Only events/metadata over MQTT, no continuous raw stream.
- **ESP32 (ESPHome)** — near-real-time I/O (buttons, encoder, LD2410B radar) and slow
  environment sensors (BME280). Deliberately the cheap, replaceable front panel.
- **NAS-Pi 5** — MQTT broker (Mosquitto), dashboards, storage. Already in place.

## Domains and where things belong

The project has several domains. When creating new artefacts, hit the right domain:

| Domain | Tool / format | Planned location |
|---|---|---|
| Enclosure (CAD) | CadQuery (Python), parametric, export STEP/STL | `cad/balkon_borg.py` |
| Carrier board (sensor carrier) | netlist from code (SKiDL) → Aisler; Python for output/DRC/BOM | `pcb/` |
| ESP32 firmware | ESPHome (YAML) | `firmware/esphome/` |
| Light | WLED config, presets, button mapping | `wled/` |
| Backend services | Podman quadlets (Mosquitto, Frigate, readsb/tar1090, BirdNET-Go) | `deploy/quadlets/` |
| Wiring | terminal assignment, GPIO/I²C/Wago plan | `docs/wiring.md` |

Create directories only when the first real content appears, not on spec.

## Important doc files

- **[`docs/enclosure-sintering.md`](docs/enclosure-sintering.md)** — enclosure manufacturing:
  **SLS/PA12 black**, SLS design rules, printed parts, providers (Germany first).
- [`docs/build-notes.md`](docs/build-notes.md) — integration/build (Pi5 power, ESP flash,
  WiFi, print, hardware checklist).
- [`docs/power-distribution.md`](docs/power-distribution.md) — 5 V star + branch fuses.
- [`pcb/docs/board-spec.md`](pcb/docs/board-spec.md) — binding board template.

## Conventions for this project

- **Chat in German, everything written in English** — code, identifiers, comments,
  documentation and commit messages are English; chat replies to the user are German.
- **CAD is code, not a click model**: `cad/balkon_borg.py` stays parametric. Real
  dimensions (board measurement, insert/diffuser fit) as named parameters at the top
  of the file, not magic numbers in the body.
- **Metric dimensions**, mm as the default CAD unit. Document tolerances.
- **Safety is non-negotiable**: 230 V strictly separated from the printed enclosure
  (PSU external). The printed part carries low voltage only. With every
  electrical/thermal proposal, think about fire safety and fusing.
- **MQTT** is the bus. New data sources get a clear topic scheme; record the scheme in
  the log once it is fixed.
- **Low-solder preferred**: pre-flashed/pluggable parts over self-build, as long as the
  quality holds (preference: quality over price).
- **Size up generously (ergonomics).** The user has big fingers and is rather clumsy:
  board and enclosure may be larger. Controls, connectors and screws well apart, no
  cramped layouts or fiddly micro-connectors, no dense hand soldering. When in doubt,
  bigger rather than more compact.

## Keep the decision log (important)

As soon as a non-trivial decision is made (part choice, GPIO assignment, topic scheme,
dimension/tolerance decision, scope change, rejected alternative), **append a dated
entry to `log/decisions.md`**. Format and example are in the head of that file. The log
is the project's memory layer: it stops already-settled questions from being reopened.

Do not log what is already in the code/YAML. Log *why* it is that way and which
alternative was rejected for which reason.

## Next steps

Current state and open points: see `README.md` §8 and the most recent entries in
`log/decisions.md`.

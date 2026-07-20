# src — Software stack

The application software for Balkon-Borg: what runs on the borg-pi5, the ESP32 (as an
application, not just its config), the Android app, and what the two sides share.
Complements the hardware side (`cad/`, `pcb/`, `wled/`, `docs/`), which keeps its own
[decision log](../log/decisions.md). This directory has its own
[`CLAUDE.md`](CLAUDE.md) and [decision log](log/decisions.md) — read those first for
anything in here, not the hardware log.

## Layout

| Path | Purpose |
|---|---|
| `pi/` | Software running on the borg-pi5 hub: orchestration/MQTT-side logic, plus the Podman quadlets in `pi/quadlets/` (Mosquitto, Frigate, readsb/tar1090, BirdNET-Go). |
| `esp/` | The ESP32 application (moved from `firmware/esphome/`): ESPHome config reading the buttons/encoder/radar/BME280 and driving WLED over MQTT. |
| `android/` | The phone app. |
| `shared/` | **The interface contract** ([`shared/README.md`](shared/README.md)): all MQTT topics/payloads, HTTP endpoints/ports, media storage paths — authoritative for borgd, ESP, app and services. Runtime config (`borg.yaml`) joins it. |

## Architecture

The whole-system concept — components, mode system, resource arbitration, overlay
priority, and the graceful-degradation story when the borg-pi5 is off — is in
[`architecture.md`](architecture.md) (the Gesamtkonzept, currently under review). The
per-decision reasoning is in [`log/decisions.md`](log/decisions.md).

## Mode architecture (decided, mechanism only)

Concurrency/scheduling and the app-vs-automation priority question are resolved as a
**mode mechanism** — see [`log/decisions.md`](log/decisions.md) (2026-07-16) for the
full reasoning. Summary: **one retained state topic per main mode** on MQTT
(`balkon/mode/<main>` + `balkon/mode/focus`; the authoritative contract is
[`shared/README.md`](shared/README.md)), read by every mode-dependent service;
**manual selection (app/buttons) pins the mode**, and without an active pin
**automatic triggers** (radar/time/presence) set it — so a manual choice always wins
while pinned. One arbitration component on the **borg-pi5** owns writing the mode. A small **baseline** (BME logging, broker/dashboards, basic radar
motion log) runs regardless of mode, but only while the borg-pi5 itself is powered (it
is not 24/7). The mode → per-service mapping (WLED preset, SDR owner, gesture
detection, Frigate intensity, ...) lives in one central declarative config, not
hardcoded per service.

## Not yet decided

This is still a skeleton, not a build. The mode *mechanism* above is settled, and the
use cases are settled in [`../docs/use-cases.md`](../docs/use-cases.md) (all 20 are
binding); these still need answers:

- **Build order.** Which of the 20 use cases to implement first — this also shapes the
  concrete presets and what the Android app controls vs. only observes.
- **The concrete presets** (named feature bundles) and their per-feature settings —
  depends on the above.
- **Automatic-trigger heuristics** — what radar/time/presence pattern proposes which
  mode, and whether a manual pin ever times out on its own.
- **Config format and home** for the mode → settings mapping (likely `shared/`, format
  TBD).
- **Stack/language choice for `pi/`** — not fixed yet. (`android/` is decided:
  Flutter/Dart, see [`log/decisions.md`](log/decisions.md).)

Once a first slice of use cases is picked, the high-level architecture (component
diagram, data flow, the concrete mode list) belongs here as the next real content,
backed by an entry in [`log/decisions.md`](log/decisions.md).

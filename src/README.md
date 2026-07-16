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
| `shared/` | Contracts both sides depend on (MQTT topic/payload schema, currently sketched in [`../docs/network.md`](../docs/network.md); formalise here once code needs it, not before). |

## Not yet decided

This is a skeleton, not an architecture. Before any of the above grows real code, the
following need answers — deliberately deferred until the use cases that drive them are
picked (see [`../docs/ideas.md`](../docs/ideas.md), the candidate pool):

- **Which use cases get built first.** The idea pool has 100+ candidates; the
  architecture (what has to run continuously vs. on demand, what owns the single
  RTL-SDR tuner, what the Android app controls vs. only observes) depends on the
  selection.
- **Concurrency / scheduling.** Several use cases want the same limited resources at
  once (the SDR tuner, the camera, the light). Something has to arbitrate between them
  — not designed yet.
- **Priority model.** Does an Android app command always pre-empt automation (radar,
  scenes)? Does MQTT from the ESP32 win over the app, or the other way round? Open.
- **Stack/language choices** for `pi/` and `android/` — not fixed yet.

Once a first slice of use cases is picked, the high-level architecture (component
diagram, data flow, the scheduling/priority model above) belongs here as the first real
content, backed by an entry in [`log/decisions.md`](log/decisions.md).

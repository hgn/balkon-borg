# CLAUDE.md — src/ (software stack)

Scoped conventions for the Balkon-Borg software stack. Complements the top-level
[`../CLAUDE.md`](../CLAUDE.md) (language, filenames, git conventions still apply here)
and is its software counterpart: hardware minutiae (wall thickness, connector part
numbers, wiring) live in `../log/decisions.md` and `../docs/` and are **not** required
reading for work in this directory.

## Always read first (for anything under src/)

1. This file.
2. [`README.md`](README.md) — layout and the open architecture questions.
3. [`log/decisions.md`](log/decisions.md) — the software decision log. Before
   re-opening a design question (stack choice, protocol, data contract, scheduling
   rule), check whether it is already settled there.

## Domains

| Path | Covers |
|---|---|
| `pi/` | borg-pi5 orchestration + `pi/quadlets/` (Podman: Mosquitto, Frigate, readsb/tar1090, BirdNET-Go) |
| `esp/` | ESP32 application (ESPHome config) |
| `android/` | Phone app (Flutter/Dart) |
| `shared/` | The interface contract (`shared/README.md`: MQTT topics/payloads, HTTP endpoints, media paths — authoritative) + runtime config (`borg.yaml`) |

Create files only once the first real content appears, not on spec — see
[`README.md`](README.md) for what's still genuinely undecided (use-case selection,
concurrency/scheduling, priority model, stack choices).

## Keep the decision log (important)

As soon as a non-trivial software decision is made (stack/language choice, protocol,
data contract, scheduling/priority rule, rejected alternative), append a dated entry to
[`log/decisions.md`](log/decisions.md) — same format as the hardware log's head. Do not
log what is already in the code; log *why*.

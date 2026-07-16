# Decision log — Balkon-Borg software stack

Chronological log of **software** decisions (architecture, protocols, data contracts,
stack/language choices, scheduling and priority rules). Append newest entries at the
top. Purpose: to record *why* the software is the way it is, so settled questions are
not reopened.

Hardware decisions (enclosure, PCB, manufacturing, wiring, power) are logged separately
in [`../../log/decisions.md`](../../log/decisions.md) — split so neither side has to
wade through the other's context. See that file's 2026-07-16 entry ("Software stack
split into src/") for why.

**Entry format:** identical to the hardware log's, see its head for the template.

---

## 2026-07-16 — Mode architecture: one global mode, manual pins, central config

**Context:** two of `src/README.md`'s open questions (concurrency/scheduling, the
priority model) needed a mechanism. Trigger was concrete: MediaPipe pose/gesture
detection on the Pi 5 (8 GB) measures ~60-70% CPU at a usable frame rate (source:
a Hackaday log benchmarking MediaPipe 0.10.18 on exactly this board), which cannot run
continuously alongside Frigate's own CPU-bound object detection — and the single
RTL-SDR tuner already can't serve ADS-B (readsb) and FM/DAB+/shortwave listening at
the same time. Something has to decide, at any moment, what the borg-pi5 is actually
doing. Resolved via `interview-me` (four architecture-level questions, one at a time).

**Decision:**
1. **One global mode**, a single value published on MQTT (e.g. `balkon/mode`:
   `home` / `party` / `away` / `night` / `listening` / ... — the closed list is not
   fixed yet, see below). Every mode-dependent service reads that one topic.
2. **Manual selection pins the mode.** The app or the physical controls (button/
   encoder) set the mode explicitly, and it stays pinned until changed again or
   explicitly released back to automatic. Without an active pin, automatic triggers
   (radar pattern, time of day, presence/absence) set the mode. This is also the
   answer to the standing "does the app override MQTT/automation?" question: yes,
   for as long as it is pinned.
3. **One arbitration component owns writing the mode topic** (avoids competing
   writers) and runs on the **borg-pi5** — user's explicit call: "das Gehirn sollte
   immer der Pi sein, da läuft ja auch der MQTT broker."
4. **Baseline services run regardless of mode**: BME280 environment logging, the
   MQTT broker + dashboards, and a basic radar motion log. Only the expensive or
   mutually-exclusive things are mode-gated (WLED scene, gesture detection, SDR
   ownership, Frigate intensity). Note this baseline is "always on" only while the
   borg-pi5 itself is powered — it is explicitly **not** 24/7 (see the hardware
   log's 2026-07-11 entry); WLED's own onboard presets/schedules remain the only
   layer that runs independent of the Pi.
5. **Mode → per-service settings is a central declarative config** (e.g. a
   `modes.yaml`, home to be decided — likely `src/shared/`, format TBD), not
   hardcoded per service. Adding or tuning a mode is a config edit, not a
   multi-service code change.

**Rejected:**
- **Multiple independent axes** (e.g. separate `social_state` / `sdr_owner` /
  `vision_load` topics) instead of one global mode — more flexible, avoids forcing
  some combinations, but more moving parts and combinations to reason about /
  test. Revisit if a single mode value turns out too coarse once real modes exist.
- **Manual-only** switching — simpler, fully predictable, but breaks automatic-
  trigger use cases already in the idea pool (away/security detection, "welcome
  home" on presence) that must not depend on someone remembering to flip a switch.
- **Automatic-only** switching — risks guessing wrong (e.g. reading "nobody moving"
  as "alone" during a low-motion party); contradicts the user's own framing of
  modes as something they explicitly choose ("wenn Party ist... wenn ich alleine
  bin").
- **Hardcoded per-service mode mapping** — works, but a new/tuned mode would touch
  code in every subscribing service instead of one config file; inconsistent with
  the project's existing code-/data-driven ethos (parametric CAD, netlist-from-code).

**Explicitly still open (deferred on purpose, depends on which use cases get built
first — see [`../docs/ideas.md`](../docs/ideas.md)):**
- The actual closed list of mode values.
- Concrete per-mode settings (which WLED preset, which SDR owner, etc. per mode).
- Pin timeout / auto-release behaviour (does a pin ever expire on its own?).
- The automatic-trigger heuristics (what radar/time pattern proposes which mode).
- Config file format and its exact home under `src/`.
- Stack/language choices for `pi/` and `android/`.

**Consequences:** `src/README.md`'s "Not yet decided" list updated — concurrency and
priority are no longer open (see this entry), the rest above stays open. The mode
config becomes the first concrete candidate content for `src/shared/`.

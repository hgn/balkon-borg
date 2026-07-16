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

## 2026-07-16 — REVISION: features are combinable, gated by a resource table

**Supersedes the core of the three earlier mode entries below** (one global exclusive
main mode; submodes mutually exclusive; Radio-vs-Scanner as exclusive main modes). Two
user corrections forced the revision:

**1. Power is all-on/all-off.** The whole unit powers as one off the single 5 V feed —
borg-pi5, ESP32 and WLED together, or nothing; no per-branch switch. So there is **no
"Pi off but panel on" state**. This voids the entire graceful-degradation concern the
architecture draft had raised (broker-on-Pi coupling, ESP↔WLED decoupling): the broker
is always up whenever the panel is. It also corrects the earlier assumption (hardware
log 2026-07-11, and `docs/network.md`) that WLED was independently powered and ran its
own presets while the Pi was off — it is not; unit off = everything off. `network.md`
fixed accordingly.

**2. Modes are NOT mutually exclusive — features combine in parallel.** The user runs
e.g. Ambient light *and* airband listening at once, or turns airband off while keeping
Ambient. Only *some* combinations clash, always because **two features need the same
exclusive resource**. So the model becomes:
- independently-toggleable **features** (the former submodes),
- a small set of **exclusive resources** (SDR tuner · Vision = camera+heavy CPU ·
  Speaker · Matrix-whole-panel), plus **shared** ones that never clash (Mic — fan-out;
  Matrix per-row; BME/dashboards/logging),
- rule: **two features are compatible iff their exclusive-resource sets are disjoint.**
The old "main modes" (Licht/Party/Radio/Scanner/Away) survive only as **presets** —
named bundles of feature toggles you start from and then adjust, not exclusive states.

**Tooling decision (the user's actual question):** to work out what clashes, use a
**resource-allocation table** (feature → exclusive resources needed), **not** an N×N
feature-vs-feature matrix. Rationale: conflicts are resource-driven, not arbitrary
pairs, so the resource table is far smaller, explains *why* two things clash, captures
the "verschachtelt" nature naturally (a feature clashes with another only where their
resources overlap, which differs per pair), and is directly the implementation (the
allocator grants/denies resources). First draft of the table is in
[`../architecture.md`](../architecture.md) §4, to be completed together.

**What still holds from the earlier entries:** the manual-pins-over-automatic priority
rule; one arbiter on the borg-pi5 owning the writes; the overlay/speaker priority model
(§5); the baseline/shared-service/overlay/control-surface split. What changed is only
the exclusivity assumption — from "one mode at a time" to "many features at once,
resource-gated."

## 2026-07-16 — All 20 use cases placed on the mode tree

**Context:** with `docs/use-cases.md` holding the binding 20 use cases, sort them onto
the mode structure so the architecture has a shape before any code. Full map lives in
that file's "Mode placement (overview)" section; this records the decisions and the
one real fork.

**Main modes:** Licht, Party, Radio, Scanner, Away. **Radio vs Scanner is the fork**
the user resolved: rather than one "Funk" main mode with everything as submodes, or
ADS-B as a silent tuner default, the SDR splits into two peer main modes — **Radio**
(active listening, audio out: FM/DAB+/shortwave/airband) and **Scanner** (data decode:
ADS-B/rtl_433/APRS/radiosonde/spectrum/pager/LoRa/scheduled NOAA-ISS-meteor captures).
Both contend for the single tuner, so they're mutually exclusive at the main-mode
level. *Night* is a **modifier** (shifts thresholds/scenes inside the active mode),
not its own main mode.

**Non-mode buckets:**
- **Baseline** (always on while the Pi is powered): U4 environment/Grafana/heatmap,
  U6 BirdNET, U18 daily time-lapse.
- **Shared services** (used by modes, not modes): U7 camera/Frigate (radar-gated),
  the speaker/audio path.
- **Overlays / interrupts** (event-driven, cross-mode, priority rule still TBD):
  U9 audio/TTS feedback, U11 alarm, U12 intercom, U19 presence ghost, U9.3 storm
  warning.
- **Control surface** (not a mode): U2 buttons/clap/gesture.

**Rejected (the SDR fork):** one "Funk" main mode with all SDR uses as flat submodes
(simplest, but ADS-B then never runs unless explicitly picked); ADS-B as the tuner's
default background job that Radio preempts (keeps ADS-B "just on," but the user
preferred an explicit Scanner mode).

**Consequences / open:**
- **SDR data freshness:** because neither Radio nor Scanner is the idle default,
  SDR-derived data (U3.2 flight ticker, U13 sensor net) is only fresh while Scanner
  runs. Open whether ADS-B/Scanner should be the tuner's idle default so those tickers
  stay live — deferred.
- **DAB+ EWF (U10.4)** only catches warnings while tuned to DAB; the single tuner
  can't monitor it in the background. Accepted limitation, not a bug.
- The **overlay priority rule** (what interrupts what: does an intercom call override
  a storm warning? does the alarm override everything?) is now the next real open
  question, alongside the still-open per-mode settings and automatic-trigger
  heuristics.

## 2026-07-16 — Submodes are mutually exclusive → they arbitrate shared resources

**Context:** U1 (distance-based light + a proximity bar on the matrix's top row) and
U3 (a scrolling-text ticker, also wanting the top row) collided over who owns that
row. The main/sub structure (previous entry) turns out to already resolve it.

**Decision / insight:** within a main mode, exactly one **submode** is active at a
time, and submodes are **mutually exclusive**. That makes the submode the natural
arbiter of any resource shared inside a main mode: the two claimants just become two
submodes, and only one is ever live. Concretely, under the **Licht** main mode:
- **"Distance Detector"** submode = all of U1 (presence fade-in, distance-scaled
  brightness, the top-row proximity bar, the departure flicker).
- **"Info Ticker"** submode = U3's scrolling-text requirements (time/temp/flight/
  bird-of-the-day on the matrix).
- plus the plainer light submodes (normal / ambient / cozy — the last folded in from
  Button 2's old "scene cozy").
The proximity bar and the ticker can never run at once because they are different
Licht submodes, so the top-row conflict simply doesn't arise. User's framing:
"Distance Detektor Submodus im Licht modus" and "der Info ticker ist ein spezieller
(sub) modus wieder."

**Consequence:** this is the general pattern for intra-main-mode resource contention
(the matrix, the speaker, later the camera) — express the competing behaviours as
sibling submodes rather than trying to run them concurrently. Cross-*main*-mode
contention for the single global resources (the SDR tuner, heavy CPU) is still the
main mode's job, as before. `docs/use-cases.md` U1 and U3 updated with their submode
placement. The Licht submode list is illustrative, not yet closed.

## 2026-07-16 — Mode value gets structure: main mode + submode

**Context:** the mode list is growing past simple flat values as `docs/use-cases.md`
takes shape — e.g. U10 "Radio" has four internal choices (FM/DAB+/shortwave/EWF),
U2 wants several light-specific sub-behaviours (normal/ambient/cozy/…). A single
flat `balkon/mode` value can't express "which one, within Radio" cleanly, and there
aren't enough physical buttons to give every option added over time its own control.

**Decision:** the mode value gets a **second, dependent level**: `balkon/mode`
(main mode: Licht / Radio / Party / Away / Night / …) and `balkon/mode/sub`
(submode, meaningful only relative to whichever main mode is currently active — "FM"
only means something when the main mode is Radio). This is a **tree, not the
rejected independent-axes design** from the first mode-architecture entry above:
exactly one main mode is active at a time, and its submode is scoped to it, not a
free product of several simultaneously-combinable dimensions.

**Physical control (buttons), reassigned:**
- **Button 3**: main-mode cycle, short press advances, long press releases an active
  pin back to automatic (unchanged from the earlier entry).
- **Button 2**: submode cycle *within the current main mode* (repurposed — its old
  "scene cozy" role becomes just one submode value under main mode "Licht", not a
  separate button function).
- **Button 4**: freed up. It used to toggle "presence automation on/off", which now
  overlaps with Button 3's long-press. Not reassigned yet.

Only a **curated, small subset** of each main mode's submodes gets a button-reachable
slot (e.g. Radio: FM/DAB+/off cycle on Button 2, not the full four requirements) —
buttons are the fast/common path. The **app can address the full main-mode/submode
space**, including submodes with no button shortcut at all and ones added later.
This is the user's own framing, stated directly: physical controls can't keep up
with "which [modes] come" over time, so the app is the complete, authoritative
control surface and the buttons are a convenience shortcut into part of it.

**Rejected:** giving every submode its own button (impossible, only 4 buttons +
encoder exist and 2 are already spoken for elsewhere); keeping Button 4's old
"automation on/off" meaning unchanged (redundant with Button 3 long-press once the
mode system is the actual source of truth for "automatic").

**Consequences:** `docs/use-cases.md` U2's button-role description updated to match.
`src/esp/README.md`'s "planned" note needs a second line for Button 2 once this is
implemented (still not implemented — no mode list exists in code yet, same caveat as
the first mode-switch entry).

## 2026-07-16 — Android app: Flutter/Dart

**Decision:** the phone app (`src/android/`) is built in **Flutter/Dart**. User's
choice, stated directly.

**Consequences:** `android/` will hold a standard Flutter project once code starts.
Follow-on choices not made yet: the MQTT client library (e.g. `mqtt_client` is the
common pure-Dart option), and whether the cross-platform reach Flutter gives for free
(iOS) is ever used — the project is scoped as an Android app, nothing changes that
here. Removes "stack/language choice for `android/`" from `src/README.md`'s open
list; `pi/`'s stack choice is still open.

## 2026-07-16 — Mode switch: reuse an existing button, no new hardware

**Context:** the mode mechanism (previous entry) needs a physical way to cycle modes.
User initially asked for "a dedicated switch." Both the enclosure (re-ordered
2026-07-15 with the reviewed geometry) and the carrier PCB (ordered 2026-07-14, in
fabrication at Aisler) are already committed with exactly 4 buttons + 1 encoder wired
— no spare connector or bore for a sixth control.

**Decision:** **Button 3** (currently "scene party," GPIO27) becomes the general
mode-cycle control: short press = advance to the next mode; long press = release an
active manual pin back to automatic. Firmware-only change in `src/esp/`, to be made
once the mode list and the Pi-side arbiter exist — **not implemented yet**, no mode
values are defined. Rest of the mapping stays: Button 1 on/off, Button 2 scene,
Button 4 automation toggle, encoder turn/push brightness/light-off.

**Rejected:** a new physical switch — needs a new enclosure bore (a fourth CAD/order
cycle, on top of an order paid barely a day ago) and a new PCB header (board respin;
the current board is already in fabrication). Not worth it for a function achievable
entirely in firmware.

**Display (proposed, not yet built):** mode identity shown two ways. The Android app
reads `balkon/mode` directly — already covered by the mode architecture, no new work.
The WLED panel gives a brief (~2-3 s) visual confirmation on every mode change
(scrolling mode name or a mode-specific colour flash, using the matrix's existing 2D
text capability — see ideas 21/27 in `../../docs/ideas.md`), then reverts to that
mode's normal light behaviour. Button 3's own LED can double as a lightweight binary
indicator (lit = a manual pin is active, off = automatic) — it cannot show *which*
mode (single-colour ring LED, not addressable), so mode identity stays the panel's/
app's job.

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

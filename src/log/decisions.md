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

## 2026-07-16 — Per-mode power-on defaults + Munich station lists

**Power-on defaults** (each region boots into a chosen submode, highlighted amber in the
§3 diagram): **LUMEN → ticker** (visible it's on, not distracting), **SDR → off**,
**Camera → gesture** (you're present when you flip the mains), **SENTRY → off**, speaker
silent. Boots visible-but-calm, present-aware, quiet.

**Munich station lists** (Button 3 sub-submodes under COMMS, real frequencies, default
first): **FM** — Bayern 3 · 97.3 (default) / Antenne Bayern · 101.3 / Gong · 96.3 /
Energy · 93.3 / Charivari · 95.5. **DAB+** — Deutschlandfunk (default) / Bayern 3 / BR24.
**Shortwave** — free tune, no list. **Airband** (EDDM, Laim-receivable, picked for
"where the action is") — ATIS · 123.13 (default, always-on loop) / Approach · 127.95
(busiest, aircraft transmit from altitude so it reaches the city) / Director · 118.82 /
Tower · 118.7. Lists live in the mode config (`src/shared/`), editable without code.

**Diagram:** the deep 5-level nesting (region → SDR → COMMS → FM → station) broke mermaid
("rank" error), so the station detail is a **second, focused COMMS diagram** (3 levels)
beside the main mode diagram; both validated. Defaults are marked with a `classDef` amber
highlight rather than only the initial-state arrow. **Still open:** the SDR idle default
(off vs. a silent ADS-B) and the SIGINT/ADS-B behaviour for low overflights near Laim —
to clarify.

## 2026-07-16 — Mode names: LUMEN / COMMS / SIGINT / SENTRY (ops/tactical)

The four main modes get an **ops/tactical** naming (the user's pick from a naming
brainstorm of five schemes — Borg / cyberpunk / ops / German-fun / elemental):

| Mode name | Function | was |
|---|---|---|
| **LUMEN** | the light panel (ambient…effects) | Licht |
| **COMMS** | SDR listening (FM/DAB/shortwave/airband) | Radio |
| **SIGINT** | SDR data decode (ADS-B/rtl_433/APRS) — *signals intelligence*, genuinely the right term | Scanner |
| **SENTRY** | security/surveillance when away | Away |

These are the mode names throughout the live spec and the UI (panel + app; the MQTT
values too). Submodes follow the same tone. **Rejected:** the other four schemes, and
the weaker ops picks ILLUM (for LUMEN) and OVERWATCH (for SENTRY). Earlier decision-log
entries used the functional names (Licht/Radio/Scanner/Away); this entry is the mapping,
history is not rewritten. Use-case *titles* (e.g. U10 "Radio") keep their descriptive
names — a use case is a feature, a mode is the button-1 focus that runs it.

## 2026-07-16 — U3 specified: effects as WLED presets, simple visualiser

**Decision:** the effect scenes (disco / strobe / rotating blue-red police) are **WLED
built-in presets** on the Athom controller — no custom firmware; the arbiter selects the
preset over MQTT when Button 2 lands on that Licht submode. The **visualiser is a simple
level/beat pulse**: the Pi measures the mic amplitude/beat and publishes it, the arbiter
maps it to a WLED effect's intensity so the panel pulses to the music. **Rejected:** a
full FFT-spectrum bar display streamed as realtime pixels (Pi → DDP/E1.31) — too much
effort (pixel streaming, latency tuning, bypassing WLED's engine) for the payoff on an
8×25 panel. All U3 lives as Licht submodes (no Party main mode). Full write-up in
`docs/use-cases.md` U3.

## 2026-07-16 — Buttons = the three mode levels in order; main mode is the focus

**Supersedes the button assignments** in the two entries below (Button 3 = main mode,
Button 2 = submode, Button 4 = sub-submode). User's call, specifying U2/U3.

- The three mode levels sit on the **first three buttons in order**: **Button 1 = main
  mode, Button 2 = submode, Button 3 = sub-submode.** **Button 4 = reserve.**
- **Main modes are parallel and independent**, each always in an **active submode**, and
  **every submode list includes an explicit "off"** — that is how a main mode is switched
  off (Button 2 to *off*), not a separate button. So Licht off + Radio on, or the reverse,
  in any combination. Button 1 is the *focus* — which subsystem the buttons steer (Licht /
  Radio / Scanner / Away) — not an exclusive state: switching focus to Radio does **not**
  stop the disco light, it just moves what Button 2/3 control. Reconciles the button
  hierarchy with the parallel-axes model and "Disko ist Disko, egal was der Empfänger
  tut". Long-press Button 1 releases a manual pin to automatic.
- **Displacement on resource conflict only.** Most main modes coexist (different
  resources). Where two need the same exclusive resource — Radio and Scanner both need
  the one SDR tuner — turning one on **displaces** the other to *off*. The arbiter
  enforces the §4 resource table; displacement happens only when such a conflict exists
  ("falls es diesen Fall gibt").
- **No device on/off button.** Button 1 used to be light on/off; the user switches the
  whole unit at the mains (power strip), so a device toggle is pointless and a light
  toggle is redundant (the scene list has "off", the radar auto-ons in the evening).
  Button 1 is repurposed to the main mode; the light-off is a Licht submode.
- **Panel/light is one flat program list** (Party main mode dissolved): under focus
  Licht, Button 2 cycles ambient / full / cozy / distance-auto / ticker / disco / strobe
  / police / … / off. The former "Party" effects are just Licht submodes. Encoder and
  clap/gesture unchanged from the "Control map refined" entry (turn = brightness/volume,
  push toggles target; clap gated; full gesture vocabulary).

## 2026-07-16 — Control map refined: Button 4 = sub-submode, encoder does volume too

**Refines the button map** from the earlier mode-switch entries (Button 4 was "free",
encoder push was "light off"). From specifying U2.

- **A third mode level.** Some submodes carry a list — Radio/FM has stations, Radio/
  airband has frequencies (Munich Tower/Approach/…), Scanner/ADS-B has filter presets.
  So the mode tree gains an optional **sub-submode** (`balkon/mode/chan`), used only
  where a submode has a list; inert otherwise. User's idea.
- **Button 4 = cycle the sub-submode** (next station/frequency/preset within the current
  submode). Replaces its "free/mute" placeholder.
- **Encoder push toggles what the knob controls (brightness ↔ volume)**, turn adjusts the
  current target, the panel shows which. Dropped the old "push = light off" — Button 1
  already does off, and there are now *two* continuous quantities (light brightness and
  audio volume) that one encoder must serve. Automatic context-switching was rejected:
  when light and radio are both on it is ambiguous, so an explicit toggle wins.
- **Clap (U2.2)** kept but **gated to quiet contexts** — disabled while the speaker plays
  loud (Party mode / radio/media), else it false-triggers or is masked. Lightweight
  spike/two-in-a-window detector on the Pi mic (fan-out, cheap).
- **Gesture (U2.3)** kept at full vocabulary (5 fingers on, fist off, thumbs scene, swipe
  dim, finger count = preset). Honest limit recorded in the use case: it needs light to
  see the hand, so the evening auto-on stays the radar's job, not a gesture in the dark.

Full write-up in `docs/use-cases.md` U2; `src/architecture.md` §8 gains the third topic.

## 2026-07-16 — Drop InfluxDB + Grafana: live-only, no telemetry database

**Supersedes item 3 of the "Software service stack fixed" entry below** (InfluxDB v2 +
Grafana as the telemetry store).

**Context:** specifying U4, the user noted that persisting BME data across the unit's
downtime is a data grave with no value, and asked why an InfluxDB at all. That was the
*last* real consumer of the telemetry DB, so the question cascades to the whole stack.

**Decision:** **no InfluxDB, no Grafana.** Every service that needs history already keeps
its own store and UI — tar1090 (aircraft), BirdNET-Go (birds), Frigate (recordings),
Netdata (system health). The unit's own live data (environment, presence, mode) stays on
MQTT; the arbiter holds a short **in-RAM ring buffer** for recent trends (e.g. the BME
pressure trend for U4). The **Flutter app is the live dashboard** for that data
(subscribes to the topics, keeps a short trend while connected); the matrix Info-Ticker
can surface a value too.

**Rationale:** matches the user's "kein Datengrab" line — the device is all-on/all-off,
so a persistent time-series DB would mostly store gaps, and each capture service already
owns its domain UI. Dropping both removes two containers, a database and its retention/
downsampling upkeep, and RAM/maintenance load, for no loss (nothing wanted the unified
historical pane badly enough to justify it — the diagnostics/tricorder idea was rated
skip).

**Rejected:** keeping InfluxDB+Grafana for mode/event history + a unified glance pane
(the data grave the user is avoiding; no use case needs it); keeping Grafana live-only on
an MQTT datasource (contrived, and the app already is the live dashboard).

**Consequences:** `architecture.md` §1 (drop the telemetry row), §8 (no telemetry DB
note) and §9 (reverse-proxy list, resolved list) updated; `README.md` goal, `docs/
design-review.md` U4 line, and `docs/use-cases.md` U4 implementation updated. The
Podman-quadlet set to build shrinks accordingly (no influxdb/grafana units).

## 2026-07-16 — U4 reduced to live environment only (no long-term log / heatmap)

**Context:** specifying U4 (`docs/use-cases.md`). It had wanted a long-term climate log
and a presence usage heatmap.

**Decision:** U4 is **live-only** — current BME values + a short recent/session trend.
Both historical requirements are dropped, because the unit is all-on/all-off and runs
only when needed: a "long-term" climate log would be full of gaps (nothing logged while
off), and a presence "usage heatmap" would be circular (the unit is on *because* someone
is there, so it mostly plots its own on-time). Shipping either would be a misleading
half-record.

**Consequence for the stack:** no persistence at all for BME — an in-RAM ring buffer in
the arbiter serves the recent trend (see the next entry, which drops InfluxDB/Grafana
wholesale). Radar
presence stays live for U1/mode logic but is no longer logged. Environment *alerts*
(frost/heat/storm) are not U4; they live in their own use cases (e.g. U9.3). Full
write-up in `docs/use-cases.md` U4.

## 2026-07-16 — Vision axis is presence-scheduled; safe power-on defaults

**Context:** the user questioned why Frigate at all, given MediaPipe (the pose/hand
framework from the Hackaday Pi 5 benchmark) is already in for gestures — and whether
both fit in 8 GB and perform. Both are CPU-bound (no NPU; PCIe stays free for a later
Coral/Hailo).

**Decision — keep both, time-shared on the Vision axis by presence:**
- **Present** (radar sees someone, plus a **30-minute hold** after they were last seen)
  → Vision runs **MediaPipe** for gestures/interaction.
- **Absent** (hold expired) → Vision runs **Frigate at ~2 FPS** (1 frame / 0.5 s) for
  security surveillance.
Never both at once (the Vision axis is exclusive), so the CPU is never double-loaded,
and Frigate at 2 FPS is trivial CPU-only. They are not redundant: MediaPipe does
fine-grained gesture landmarks, Frigate is a full NVR (recording, zones, object
classes, event UI) for the U11 security suite. RAM at 8 GB is workable (rough sum
~3.5–4.5 GB; the two heaviest, Frigate and MediaPipe, never coincide) — Netdata is in
to watch it. **Rejected:** dropping Frigate for a lightweight radar-triggered snapshot
(loses the NVR/review the user wants); running either continuously.

**Params:** `PRESENCE_HOLD` = 30 min, Frigate-when-absent ≈ 2 FPS. A note to watch:
MediaPipe at ~60–70 % CPU for the whole presence window may want further gating (only
while gesture features are actually plausible) — an implementation refinement, not a
design change.

**Decision — safe power-on defaults (new `architecture.md` §7):** the unit is
all-on/all-off, so every boot takes a defined calm state: automatic mode (no stale
pin survives a reboot); Panel = Distance-detector (off until presence, lights gently on
approach); SDR = off (no radio/audio on boot); Vision = presence-driven from the first
radar reading (absent → Frigate @ 2 FPS until someone is seen); Speaker = silent;
baseline up. Boots quiet, dark and safe; the everyday table light still triggers on
presence. The one open cell is the SDR default (off vs. a silent ADS-B idle), tied to
the SDR-idle-default open question.

## 2026-07-16 — Software service stack fixed (interview)

Resolved via `interview-me`, one decision at a time. Fills the stack gaps that
`architecture.md` and `src/README.md` left open.

1. **`src/pi/` language: Python** (asyncio + aiomqtt), in the existing `../.venv`. The
   arbiter is I/O-bound glue, not compute — matches the all-Python project (CadQuery,
   SKiDL, every script). *Rejected:* Go (robust single binary, but breaks the
   Python-throughout line for no real gain on an I/O daemon); Node/TS (the app is Dart,
   so no shared-types win).
2. **Config: a git-managed YAML** in `src/shared/` (features → exclusive resources,
   presets, default settings). Matches the repo's existing YAML (ESPHome, wiring
   harness), allows comments/review. The **app does not edit the file** — it sends
   commands (set mode / toggle feature) and reads derived state + the preset list the
   arbiter publishes over MQTT. *Rejected:* Python-as-code (only Python could read it,
   tuning = code change); app-writable JSON store (not versioned, no review, device is
   the only source of truth).
3. **Telemetry store: InfluxDB v2** with a thin MQTT→Influx bridge (Telegraf or ~30
   lines in the arbiter), read by **Grafana**. Purpose-built time-series with retention/
   downsampling for the BME/presence/mode/event history (U4.2 climate log, U4.3
   heatmap need real history). The capture services keep their own UIs (tar1090,
   BirdNET-Go, Frigate). *Rejected:* Prometheus (pull/metrics model is awkward for
   irregular push events); Grafana-reads-MQTT-live (no history, kills the long-term
   use cases).
4. **System monitoring: Netdata standalone** (own UI), one container, no glue, no
   second TSDB — kept separate from the app telemetry. Mainly there to watch the
   thermals under Frigate/MediaPipe load. *Rejected:* funnelling Netdata → InfluxDB →
   Grafana (more plumbing, mixes the DB); Prometheus + node_exporter (a second TSDB
   beside InfluxDB, needless for one device).
5. **Arbiter deployment: a host systemd service** (not itself containerised) that
   **starts/stops the service quadlets** to enforce resource exclusivity at the OS
   level — mode Radio stops readsb and starts the FM decoder, Scanner does the reverse,
   so only one process ever grabs the SDR dongle. Simplest control, since the same
   systemd owns the quadlets. *Rejected:* arbiter-as-container (needs the podman socket
   mounted to control siblings, more plumbing/attack surface); all SDR services staying
   up behind an MQTT lock (fragile hand-off of the exclusive `/dev` device, idle
   services waste RAM/CPU).

**Assumptions stated, not objected to (still changeable):** **Home Assistant is out** —
the custom arbiter *is* the hub; HA would overlap the arbiter, app and Grafana. **Broker
defaults:** username/password on the LAN, persistence on for retained mode/state topics.

**Still open (deferred on purpose):** build order (which use case first — the user's
sequencing call), the overlay priority ordering (proposed in `architecture.md` §5,
needs confirm), whether ADS-B/Scanner is the tuner's idle default, the automatic-trigger
heuristics, and a possible reverse proxy for the several web UIs (minor). These are
cheaper to settle when building the specific feature than to pin now.

## 2026-07-16 — Four axes, the panel is one program, drawn as parallel-region mermaid

**Refines the revision below into its final shape.** Two clarifications from the user:

- **The presence ghost owns the whole panel** ("für sich, in diesem Modus"), like any
  other visual program — not a lightweight overlay sharing rows.
- **The light/visual axis is set by hand and persists, independent of audio** ("Disko
  ist Disko, egal ob ich Radio, Flugfunk oder live singe"). A visual program is not
  overridden by whatever the SDR/speaker are doing.

This collapses the exclusive resources into **four clean axes**, each internally
one-at-a-time, mutually independent so they combine freely:
1. **Panel** (the WLED LEDs are physically *both* the ambient lamp and the 2D matrix →
   one visual program at a time: Ambient / Distance-light+bar / Ticker / Disco /
   Visualiser / Ghost). This merges the earlier separate "Matrix-whole / rows / lamp"
   into one resource, which is more honest to the single-panel hardware.
2. **SDR tuner** (off / Listen / Scanner).
3. **Vision** (off / Frigate / Gesture).
4. **Speaker** (one sound, priority-ducked per the overlay model).
Plus an always-on **baseline** (BME, BirdNET, time-lapse) with no choice, and **Mic** as
a shared (non-exclusive) input.

**Representation:** the natural picture is a **state diagram with parallel/orthogonal
regions** (one region per axis) — validated as mermaid and embedded in
[`../architecture.md`](../architecture.md) §3. It's the honest form because parallelism
*between* regions shows features combine, while one active state *per* region shows each
resource is exclusive; the FM/Airband/ADS-B/… states are the "Subzustände" the user
asked about. The §4 table is the same information in the form that becomes the
implementation (each feature declares its exclusive resources; the allocator grants).

**Consequence:** the earlier per-use-case "submode" notes (U1 Distance Detector, U3 Info
Ticker) remain valid — they're just two programs on the Panel axis, still mutually
exclusive there — so `docs/use-cases.md` needs no rewrite; the axis model subsumes them.

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
text capability — see U3 in `../../docs/use-cases.md`), then reverts to that
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
first — see [`../../docs/use-cases.md`](../../docs/use-cases.md)):**
- The actual closed list of mode values.
- Concrete per-mode settings (which WLED preset, which SDR owner, etc. per mode).
- Pin timeout / auto-release behaviour (does a pin ever expire on its own?).
- The automatic-trigger heuristics (what radar/time pattern proposes which mode).
- Config file format and its exact home under `src/`.
- Stack/language choices for `pi/` and `android/`.

**Consequences:** `src/README.md`'s "Not yet decided" list updated — concurrency and
priority are no longer open (see this entry), the rest above stays open. The mode
config becomes the first concrete candidate content for `src/shared/`.

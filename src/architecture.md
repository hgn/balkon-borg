# Architecture — Balkon-Borg software stack (Gesamtkonzept)

**Status: proposal, under joint review.** This ties the scattered mode/priority
decisions in [`log/decisions.md`](log/decisions.md) and the use-case placement in
[`../docs/use-cases.md`](../docs/use-cases.md) into one coherent picture, and
sanity-checks it for contradictions. Nothing here is built yet. Where this proposes
something *new* (not already in the decision log), it is marked **[NEW – confirm]**.

---

## 1. Components and where they run

| Component | Host | Powered | Role |
|---|---|---|---|
| **Mode arbiter** ("the brain") | borg-pi5 | on-demand | owns `balkon/mode`, resolves pin-vs-auto, applies the mode→settings config |
| **MQTT broker** (Mosquitto) | borg-pi5 | on-demand | the bus everything talks over |
| **Frigate** | borg-pi5 | on-demand | camera object detection (radar-gated) |
| **MediaPipe** | borg-pi5 | on-demand | hand-gesture input (radar-gated) |
| **readsb / radio decoders** | borg-pi5 | on-demand | the single SDR tuner's consumers |
| **BirdNET-Go** | borg-pi5 | on-demand | continuous bird-call log |
| **Dashboards / audio out (TTS, clips)** | borg-pi5 | on-demand | Grafana/tar1090; USB sound → amp → speaker |
| **Light loop** (buttons, encoder, radar, BME → WLED) | ESP32 (ESPHome) | **always on** | the fast, human-facing control loop |
| **WLED controller** | Athom board | **always on** | the light; own onboard presets run independently |
| **App** | phone (Flutter) | user's phone | full control surface, reads/writes mode over MQTT |
| **Remote access + image store** | nas-Pi5 | **always on** | minor helper, not the broker |

Physical/network path is in [`../docs/network.md`](../docs/network.md).

---

## 2. Power model: all on, or all off

The **whole unit powers as one** off the single 5 V feed — borg-pi5, ESP32 and WLED
come up together or not at all; there is no per-branch switch. There is therefore **no
"Pi off but panel on" state**, which dissolves what looked like a coupling problem:
because the broker (on the Pi) is up whenever the ESP32 and WLED are, the ESP→broker→
WLED path is always intact when it matters. Broker-on-the-Pi costs nothing here.

Consequence for the design: "baseline runs while the Pi is powered" simply means
"whenever the unit is on." Nothing needs to survive a partial power state, because
there isn't one. (This corrects an earlier assumption that WLED was independently
powered and ran its own presets while the Pi was off — it does not; when the unit is
off, everything including WLED is off.)

---

## 3. The mode model: combinable features, resource-gated  **[REVISED – confirm]**

**Correction to the earlier "one exclusive main mode" model.** Modes are **not**
mutually exclusive. Features run **in parallel** and are toggled independently — the
user's examples: *Ambient light + airband listening* together, or *airband off but
Ambient on*. Only *some* combinations clash, and always for the same reason: **two
features that need the same exclusive resource cannot both run.** Ambient (the lamp)
and airband (the tuner + speaker) share nothing, so they coexist; two radio features
(both the tuner) do not.

So the real model is:

- A set of **independently toggleable features** (the former submodes — Distance light,
  Info ticker, FM, airband, ADS-B decode, gesture, Frigate, effects, …).
- A small set of **exclusive resources** they contend for.
- A rule: **two features are compatible iff their exclusive-resource sets are
  disjoint.** Conflicts are not arbitrary pairs — they fall out of the resource map.

"Modes" (Licht / Party / Radio / Scanner / Away) survive only as **presets**: named,
convenient bundles of feature toggles (e.g. Party = effects on + visualiser on). You
start from a preset and can toggle individual features on/off, as long as the resource
allocator permits. Buttons cycle presets; the app toggles individual features.

The right tool to figure out what clashes is therefore **not an N×N feature-vs-feature
matrix** (large, and it hides *why* two things clash) but a **resource-allocation
table**: map each feature to the exclusive resources it needs, and the conflicts derive
themselves. That table is §4, and it is the thing to complete together.

---

## 4. Resource-allocation table (draft — to complete together)

**Exclusive resources** (only one user at a time): **SDR** tuner · **Vision** (camera +
its heavy CPU — Frigate xor MediaPipe) · **Speaker** (one sound at a time, ordered by
§5) · **Matrix-whole** (a full-panel effect blocks all per-row uses).
**Shared resources** (any number of users, never a conflict): **Mic** (fan-out to
BirdNET + clap + FFT + intercom at once) · **Matrix-rows** (different rows/segments
coexist) · BME, dashboards, logging.

| Feature | SDR | Vision | Speaker | Matrix-whole | (shared: Mic / rows / lamp) |
|---|:--:|:--:|:--:|:--:|---|
| Auto table light (U1) | | | | | lamp warm, row 1 |
| Info ticker (U3) | reads¹ | | | | rows |
| Effects / strobe (U3) | | | | ● | lamp RGB |
| Music visualiser (U3) | | | | ● | mic, lamp RGB |
| Radio listen — FM/DAB/SW/airband (U10,U20.2) | ● | | ● | | |
| Scanner decode — ADS-B/rtl_433/APRS/… (U5,U13,U15,U16,U17,U20.1,U8) | ● | | | | |
| BirdNET (U6) | | | | | mic |
| Clap switch (U2) | | | | | mic |
| Gesture (U2) | | ● | | | |
| Frigate / Away (U7,U11) | | ● | ●² | | |
| TTS feedback (U9) | | | ● | | |
| Intercom (U12) | | | ● | | mic |
| Presence ghost (U19) | | | | | 1 px / segment |
| Env log (U4), time-lapse (U18) | | | | | (negligible) |

¹ The ticker's *flight* line needs live ADS-B, i.e. the Scanner holding the tuner — so
a full ticker and any Radio feature clash on the tuner, even though the ticker's
time/temp lines don't. ² Only the alarm; otherwise Away is silent.

**Reading the conflicts off the table** (same ● in an exclusive column = clash):
- **SDR:** any two of {Radio, Scanner, full Info-ticker} clash — the tuner is the
  dominant bottleneck.
- **Vision:** Gesture ⟂ Frigate/Away — never both.
- **Matrix-whole:** Effects/visualiser block the ticker, the proximity bar and the
  ghost (they own the whole panel).
- **Speaker:** Radio, TTS, intercom, alarm don't *hard*-clash — they queue by priority
  (§5), one sound at a time.
- **Everything else runs in parallel.** Ambient light + airband + BirdNET + env log:
  disjoint resources, all at once — exactly the user's example.

This table is the single source of truth for "what can run together." Filling in the
last uncertain cells (does the ghost really tolerate the ticker on other rows? is a
light effect ever wanted *with* radio audio?) is the joint task.

---

## 5. Overlay priority model  **[NEW – confirm]**

Overlays interrupt whatever is playing. Proposed order, highest wins the speaker and
re-asserts until its condition clears:

1. **Alarm** (U11 security) — interrupts everything; keeps re-asserting until cleared
   or acknowledged.
2. **Safety warning** (U9.3 storm, U10.4 DAB EWF) — ducks/interrupts media + feedback;
   brief and time-sensitive.
3. **Intercom** (U12) — two-way comms; ducks radio/media while a call is active.
4. **Event feedback / TTS** (U9 bird name, flight) — plays only when nothing above is
   active; ducks radio for a couple of seconds.
5. **Ambient** (U19 presence ghost) — visual only, never makes sound; yields the
   matrix to any submode/overlay that needs it.

**Human override always wins:** an explicit app/button action is honoured immediately
(it pins the mode, §6) — except the alarm, which re-asserts until the security
condition itself is resolved. The exact ordering of 2 vs 3 (does a storm warning cut
into a live intercom call?) is the main thing to confirm here.

---

## 6. Mode changes — who writes the mode

- **Manual pin:** app or Button 3 sets `balkon/mode` explicitly → it stays until
  changed or released (Button 3 long-press) back to automatic.
- **Automatic:** with no active pin, the arbiter picks the mode from triggers (radar
  pattern, time of day, presence/absence, geofence for Away).
- **One writer:** only the arbiter (on the borg-pi5) writes `balkon/mode`, to avoid
  competing writers.
- **Buttons vs app:** Button 3 cycles main modes, Button 2 cycles submodes within the
  current main mode — a curated subset. The app addresses the full space, including
  submodes with no button shortcut.

Priority answer to the old open question: **app/manual > automation** while pinned.

---

## 7. Data flow (MQTT)

Topic scheme is in [`../docs/network.md`](../docs/network.md); the mode layer adds
`balkon/mode` (main) and `balkon/mode/sub` (submode), written only by the arbiter,
read by every mode-dependent service and by the app. The mode→per-service settings
map is a central declarative config (likely `shared/`, format TBD).

---

## 8. Open questions / risks (ranked)

1. **Confirm the combinable-feature model (§3)** and **complete the resource table
   (§4)** together — this replaces the earlier "one exclusive main mode" framing and is
   now the core of the architecture.
2. **Overlay priority (§5)** — confirm the ordering, especially safety-warning vs
   intercom.
3. **SDR data freshness** — the tuner is the dominant bottleneck; decide whether
   ADS-B/Scanner is its idle default so the flight ticker / sensor net stay live when
   no other radio feature is on.
4. **Presets** — define the named feature bundles (Licht/Party/Radio/Scanner/Away) and
   the per-feature settings + automatic-trigger heuristics.
5. **Config format and home** for the feature/preset/settings map.
6. **Stack/language for `pi/`** — the resource allocator + glue; not chosen yet.

*Resolved:* the Pi-power coupling worry (§2) is void — the unit is all-on/all-off, so
there is no partial-power state to design around.

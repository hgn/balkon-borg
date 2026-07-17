# Use cases

The authoritative, binding list: everything here gets built. Supersedes the former
`docs/ideas.md` (rated idea pool, now folded in and removed) and README §3, which
now just points here. Global, not under `src/`, because use cases drive both the
hardware (already fixed, see `log/decisions.md`) and the software stack (`src/`).

Each entry: **Requirements** (what it must do), **Value** (why it's worth building),
**Implementation** (how, concretely). Value/Implementation are filled in as we work
through the list together — entries without them yet are marked `_TBD_`.

---

## Mode placement (overview)

How the use cases map onto the mode tree (`src/log/decisions.md`). This is the sort,
not the detail — the *how* of each lives in its own section below.

**Main modes** run **in parallel and independently**, and each always sits in an **active
submode** — and every submode list includes an explicit **off**. So you turn a main mode
off by selecting its *off* submode; the others keep running (LUMEN off + COMMS on, or the
reverse, in any combination). Button 1 selects the *focus* (which main mode the buttons
steer), Button 2 cycles its submode (including off), Button 3 the sub-submode; Button 4 is
reserve.

| Main mode (focus) | Submodes (Button 2, incl. explicit *off*) | Use cases |
|---|---|---|
| **LUMEN** (the panel) | off · ambient · full · cozy · distance-auto · info-ticker · disco · strobe · police · visualiser | U1, U3 |
| **COMMS** (SDR, listen) | off · FM+RDS · DAB+ · Shortwave · Airband | U10.1/.2/.3, U20.2; U10.4 (DAB+ EWF) as a monitor under DAB |
| **SIGINT** (SDR, decode) | off · ADS-B · ISM/rtl_433 · APRS · Radiosonde · Spectrum · Pager · LoRa · scheduled captures | U5, U13, U15, U16, U17, U20.1, U8, U14 |
| **SENTRY** (security) | off · armed | U11 (auto-triggered by absence/geofence) |

*Night* is treated as a **modifier**, not its own main mode — it shifts thresholds and
scenes (dimmer, warmer, quieter). The former **Party** main mode is dissolved: its effects
(disco/strobe/police/visualiser) are LUMEN submodes (one flat program list on Button 2).

**Displacement on resource conflict only:** most main modes coexist (LUMEN + COMMS at
once — different resources). Where two need the *same* exclusive resource, turning one on
**displaces** the other: **COMMS** and **SIGINT** both need the single SDR tuner, so
switching one on drops the other to *off*. This is the arbiter enforcing the resource
table (§4 of `../src/architecture.md`); it only happens when such a conflict actually
exists.

**Baseline** (runs regardless of mode, while the borg-pi5 is powered — cheap or
always-valuable): U4 (live environment), U6 (BirdNET bird log),
U18 (daily time-lapse frame).

**Shared services** (consumed *by* modes, not modes themselves): U7 (camera/Frigate,
radar-gated — used by SENTRY and by the U2.3 gesture input), and the speaker/audio-out
path (used by U9, U10, U12, …).

**Overlays / interrupts** (event-driven, cut across whatever mode is active, need a
priority rule — TBD): U9 (audio/TTS feedback), the U11 alarm, U12 (intercom, grabs
mic+speaker), U19 (presence ghost, ambient matrix overlay), U9.3 (storm warning).

**Control surface** (not a mode): U2 (buttons / clap / gesture) is how modes are
changed and light is controlled.

**Consequences to resolve later:**
- **SDR idle default = ADS-B (resolved).** When no COMMS listening is selected, the tuner
  runs **SIGINT / ADS-B** as its silent idle (filtered to low overflights near Laim, U5),
  so the "next flight" ticker (U3.2) and the sensor net stay live. Turning COMMS on
  displaces it (single tuner); turning COMMS off returns the tuner to ADS-B idle.
- **DAB+ EWF (U10.4)** can only catch emergency warnings while the tuner is actually
  on DAB — it cannot monitor in the background during COMMS-FM/SIGINT/etc. A real
  limitation of the single tuner, not a bug to fix; the app/cell-broadcast remain the
  always-on warning path.

---

## U1 — Light at the table, automatic in the evening

**Requirements:**
1. Soft fade-in of warm-white light on presence.
2. Brightness scales with distance, not a binary on/off.
3. The matrix's top row shows a live proximity indicator: a wide bar at first
   detection (far away), narrowing to a single lit pixel at close range, off when
   nobody's present or out of range.
4. On departure, one brief flicker instead of a silent fade-out.

**Value:** the light comes on exactly when and where it's needed, without reaching
for a switch — and scaling with distance makes the transition feel deliberate
rather than jarring: it gently brightens as someone approaches the table instead of
snapping to full brightness the instant the radar sees anything at all, including
someone just passing the far edge of its range. The proximity bar gives an early,
peripheral "something's out there" cue while someone is still far off, without
competing with the main light once they're close and it's already bright — the
indicator recedes to a single pixel exactly as the real payoff (the warm light)
takes over. The departure flicker gives a clear, deliberate "goodbye" instead of the
light just quietly draining away.

**Implementation:** the LD2410B already reports a **distance value** over UART
(moving-target and static-target distance in cm), not just a presence boolean — no
new hardware, this is unused capability already sitting in the module. ESPHome's
`ld2410` component exposes it as a sensor entity. Map distance to brightness with a
curve (e.g. >4 m off, 2-4 m ramping 20-70 %, <2 m at the table 100 % warm-white),
smoothed (exponential moving average or a debounce window) so radar jitter doesn't
flicker the light. The **same distance value drives the top-row indicator**, inverted:
far away → most/all of the row's pixels lit (wide, attention-grabbing), narrowing as
distance shrinks, down to one pixel right at the table, 0 pixels when nobody's
present or the target is out of range. Runs as an independent WLED **segment** on row
1 (WLED supports addressing sub-ranges of the panel independently), so it doesn't
interfere with the main warm-white channel below it. On a presence-lost transition,
fire one short bright pulse (~200-300 ms) before fading to off, rather than a plain
fade. All of this stays **on the ESP32**, not round-tripped through the Pi: it's the
same local control loop ESPHome already owns (radar → WLED over MQTT), just enriched
with distance instead of a boolean, and it needs to feel instant. Once the mode
architecture (`src/log/decisions.md`, 2026-07-16) is live, this is the default
*within* the LUMEN main mode's **distance-auto** submode — any other LUMEN submode (an
effect scene, the ticker) simply replaces it on the panel, they don't fight.

**Mode placement:** this whole use case is the **"Distance Detector" submode of the
LUMEN main mode** (`src/log/decisions.md`). It is one light submode among others
(normal / ambient / cozy / …), selected via Button 2 or the app, not a permanent
background behaviour. Because submodes are mutually exclusive, the top-row ownership
question against U3's ticker resolves itself: the "Info Ticker" is a *different* LUMEN
submode, so the proximity bar and the ticker are never active at the same time.

**Open before building:** the "at the table" distance threshold needs on-site
calibration once mounted (real distance from the enclosure to where people actually
sit), not a value to guess from a datasheet.

---

## U2 — Manual light control without a phone

**Requirements:**
1. Physical controls: 4 illuminated buttons + rotary encoder, mapped to the mode
   hierarchy — the three levels sit on the first three buttons in order
   (`src/log/decisions.md`):
   - **Button 1 — main mode / focus**: which subsystem the buttons steer (LUMEN / COMMS /
     SIGINT / SENTRY). It switches focus only — the subsystems run in parallel, so the
     disco light keeps running while you focus COMMS and tune a station. Long press
     releases a manual pin back to automatic.
   - **Button 2 — submode** within the focused main mode; each list includes an explicit
     **off** (that is how a main mode is switched off): LUMEN → off / ambient / full /
     cozy / distance-auto / ticker / disco / strobe / police / visualiser; COMMS → off /
     FM / DAB / shortwave / airband. The main modes run independently, so LUMEN off +
     COMMS on (or the reverse) is fine.
   - **Button 3 — sub-submode** within the submode, where one exists: COMMS/FM → next
     station, COMMS/airband → Munich Tower / Approach / …, SIGINT/ADS-B → filter preset.
     Inert where the submode has no list.
   - **Button 4** — reserve.
   - **Encoder** — turn adjusts the current target (brightness *or* volume); **short
     push toggles the target** (light ↔ audio), the panel briefly shows which. (Two
     continuous quantities now, brightness and volume, so the knob's target is switchable
     rather than a redundant "off".)
2. Clap switch (2 claps) → toggle the light, as a lazy hands-free input.
3. Hand-gesture control via the camera (MediaPipe): 5 fingers = on, fist = off,
   thumbs-up = scene, swipe = dim, finger count = preset number.

**Value:** control the unit without reaching for a phone, three ways that each fit a
different moment: the buttons/encoder for deliberate, reliable control (always work,
day or night); a lazy 2-clap toggle for a quiet evening without getting up; and hand
gestures as a fun, touch-free remote when there's light to see them. Together they mean
the phone is never *required* — it is one option among several, not the only way in.

**Implementation:**
- **Buttons/encoder** are on the ESP32 (ESPHome, wired per the carrier board). Each
  press/turn becomes an MQTT message to the arbiter, which owns the mode state and the
  brightness/volume targets; the arbiter applies the change (WLED preset/brightness, or
  the audio volume). The three mode levels map to `balkon/mode`, `balkon/mode/sub` and a
  third `balkon/mode/chan` (the sub-submode). Button LEDs are driven locally by the ESP
  and can reflect state (active mode/pin).
- **Clap** runs as a lightweight energy-spike / two-within-a-window detector on the Pi's
  mic stream (fan-out alongside BirdNET, cheap). **Gated to quiet contexts** — disabled
  while the speaker is playing loud (radio/media audio active, or a lively scene) so it
  neither false-triggers nor is masked. On a clean double clap it publishes a light
  on/off command.
- **Gesture** is MediaPipe on the Pi, active only while present (the Vision axis's
  presence schedule, `src/log/decisions.md`); a recognised gesture publishes the matching
  command. Honest limit: it needs light to see the hand, so it works in daylight or once
  the panel is on — the evening auto-on comes from the radar, not a gesture in the dark.

---

## U3 — Effect / party light

**Requirements:**
1. WLED 2D effects: disco (colourful), strobe (with colour bursts), rotating
   blue-red police.
2. Scrolling-text ticker: time / temperature / next flight / welcome message.
3. Scrolling-text ticker: bird of the day.
4. Audio-reactive visualiser — a simple level/beat pulse (not a full spectrum).

**Mode placement:** all of U3 lives under the **LUMEN** main mode as submodes on one flat
program list (Button 2). There is **no separate Party main mode** — its effects are just
LUMEN submodes. So the list is: ambient / full / cozy / distance-auto (U1) / info-ticker
(U3.2/3) / disco / strobe / police / visualiser (U3.4) / … — exactly one active at a
time, which is why the ticker, the distance bar and the effects never contend for the
panel.

**Value:** the same 8×25 panel that does the everyday table light also turns the balcony
into a proper little light installation on demand — calm warm glow to full-on party board
(disco, strobe, rotating police blue-red) and a pulse that moves with the music. It makes
the unit feel intentional and fun, not a utilitarian lamp, without any extra hardware.

**Implementation:**
- The effect scenes are **WLED presets** on the Athom controller — WLED's built-in 2D
  effect engine (no custom firmware): disco = a colourful 2D effect, strobe = strobe with
  colour, police = a blue-red rotating preset. The arbiter selects the preset over MQTT
  (`wled/balkon/api {ps: N}`) when Button 2 lands on that LUMEN submode.
- The **info-ticker** (U3.2/3) uses WLED's 2D scrolling text: time/temperature from the
  BME ring buffer (U4), next flight from the SIGINT if it is running (the flight line is
  only fresh while the SDR is on ADS-B — the tuner conflict from the mode overview),
  bird-of-the-day from BirdNET, a welcome message. Content rotates or is arbiter-pushed.
- The **visualiser** (U3.4) is deliberately simple: the Pi measures the mic's amplitude/
  beat (lightweight, fan-out from the mic stream alongside BirdNET) and publishes a
  level/beat over MQTT; the arbiter maps it to a WLED effect's intensity/brightness so the
  panel pulses to the music. No per-pixel streaming — a full FFT-spectrum bar display
  (Pi → DDP realtime pixels) was rejected as too much effort for the payoff on an 8×25.
- Exactly one LUMEN submode runs at a time (Button 2), with an explicit *off*.

---

## U4 — Environment data

**Requirements:**
1. BME280 (temperature/humidity/pressure) → MQTT → dashboard: current values plus a
   short-term (recent / session) trend.

*(Dropped: the long-term climate log and the presence usage heatmap — see Value.)*

**Value:** an at-a-glance read of the balcony's conditions while you're using it — warm
and dry enough to sit out, pressure dropping so the weather is turning. Deliberately
**live-only**: the whole unit is all-on/all-off and runs only when needed, so a
"long-term" climate log would be full of gaps (no data whenever the unit is off) and a
presence "usage heatmap" would be circular (the unit is on *because* someone is there,
so it would mostly plot its own on-time). Both were dropped rather than ship a
misleading half-record; U4 shows what is true right now and the recent trend, nothing it
cannot honestly deliver.

**Implementation:** the ESP32 already reads the BME280 over I²C and publishes
`balkon/env/{temperature,humidity,pressure}` over MQTT (ESPHome), sampled every ~30–60 s
(slow signals, no need for more). No database: the arbiter keeps the recent samples in an
**in-RAM ring buffer** (a few hours' worth), which is enough to compute local trends (a
pressure drop → weather turning) and to serve the current values + short trend. The
**app is the dashboard** (subscribes to `balkon/env/*` for live values, and can request or
keep the short trend); the matrix Info-Ticker can surface a value too. Persisting BME data
would be a data grave — pointless across the unit's downtime — so it is deliberately
live-only. Radar presence stays live for the light/mode logic (U1) but is not logged.
**No alerts here:** frost/heat/storm warnings are their own use cases (e.g. U9.3 storm
warning); U4 is display-only.

---

## U5 — Aircraft reception

This is the **SIGINT** main mode's ADS-B function — and the **SDR idle default**: when no
COMMS listening is selected, the tuner runs ADS-B in the background, so this is the sky's
baseline watch.

**Requirements:**
1. ADS-B reception via readsb/tar1090 (approach MUC; optional feed to a network).
2. Two **alert triggers**, both kept rare on purpose:
   a. **Low overflight over Laim** — an aircraft within a small radius of Laim **and**
      below a (deliberately low) altitude ceiling: something you can look up and actually
      see. Rarity is tuned by keeping the ceiling low.
   b. **Special aircraft overhead** — regardless of altitude: military, government/VIP,
      an emergency squawk, a rare/heavy type, a rescue helicopter, or a first-seen
      registration.
3. **Panel ticker** on any trigger (airline + flight number + what makes it special).
4. **Spoken TTS** (+ a brief panel flash) on the *special* triggers only, so the everyday
   overflight stays quiet on the panel and only the genuinely cool stuff talks.

**Value:** the balcony watches the sky as its baseline — ADS-B is the SDR idle, so it is
always on — and speaks up only for something worth looking up for: a low jet right
overhead, or a genuinely special aircraft (the government A350, an A380, a rescue heli, an
emergency squawk). tar1090's map is there to browse, but the point is not another
flight-tracker tab; it is being *told* about the interesting ones without watching a
screen. The low altitude ceiling keeps it a treat, not noise.

**Implementation:**
- **readsb** decodes 1090 MHz; **tar1090** gives the map UI and bundles the **offline
  aircraft database** (hex → registration → type → operator) that readsb/tar1090 already
  ship — so type/operator/registration enrichment is local, no lookup service.
- The arbiter reads readsb's `aircraft.json` (position, altitude, callsign, hex, squawk)
  and applies the trigger rules: *low overflight* = distance(aircraft, Laim) < R **and**
  altitude < ceiling; *special* = hex in a military range, or callsign prefix (e.g. GAF),
  or type in a rare set (A388 / B74x / An-124 / rotorcraft …), or squawk ∈ {7700, 7600,
  7500}, or a registration not in a small persisted "seen" set (first-seen — a tiny list,
  not a data grave).
- Airline + flight number come from the callsign (ICAO airline prefix → name, e.g. DLH →
  Lufthansa). The ticker text and the TTS line are built from that + the DB enrichment.
- Announcement channels per requirement 3/4: ticker on WLED (via the arbiter), TTS via the
  speaker chain for the special triggers (subject to the overlay priority, §5), plus a
  short LUMEN flash.
- **Config** in `src/shared/`: Laim lat/lon, radius, altitude ceiling, and the
  special-aircraft rule set — all tunable.
- Runs whenever the tuner is on ADS-B (the SDR idle default), i.e. whenever COMMS
  listening is not selected.

**Open before building:** the altitude ceiling and radius (how much low traffic actually
passes over Laim) — start low, raise on site if it is too quiet.

---

## U6 — Bird-call log

**Requirements:**
1. USB microphone → BirdNET → species statistics over the season.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U7 — Camera + local recognition

**Requirements:**
1. Camera Module 3 → Frigate (people/animals) on the Pi 5 CPU.

**Value:** _TBD_
**Implementation:** _TBD_ — note: Frigate should be radar-gated (only run at full
tilt when the radar sees someone approach) rather than continuous, to coexist with
MediaPipe gesture detection (U2.3) on the same CPU; not a separate use case, just an
implementation constraint carried over from the mode-architecture discussion.

---

## U8 — Passive radio listening

**Requirements:**
1. LoRa/Meshtastic RX over the SDR (no active transmit node).
2. Surface received mesh messages on the matrix or via the speaker.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U9 — Audio feedback

**Requirements:**
1. Speaker plays a short clip / greeting when something is detected.
2. Spoken TTS event feedback: bird name, flight number.
3. Spoken storm warning on a fast pressure drop.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U10 — Radio

This is the **COMMS** main mode's listening side; each submode has a Munich station list
on Button 3 (the sub-submode). Default station highlighted.

COMMS defaults to **DAB+** (the cleanest signal), so its default station is
Deutschlandfunk.

**Requirements:**
1. **DAB+** (COMMS default submode) — **Deutschlandfunk** (default) · egoFM · BR-Klassik.
2. **FM + RDS** — the top Munich stations: **Bayern 3 · 97.3** (default) · Antenne
   Bayern · 101.3 · Gong · 96.3 · Energy · 93.3 · Charivari · 95.5.
3. **Shortwave / world-band** — a free tune (no preset list), for evening DX.
4. **DAB+ Emergency Warning Functionality (EWF)** — auto-play a warning when tuned to DAB.

**Value:** the balcony gets a real radio with a display — twist to a station, the panel
shows what's playing (RDS/label). The curated Munich lists mean the common stations are
one button away; the app reaches the rest.

**Implementation:** FM via `rtl_fm`/redsea (RDS text → panel ticker), DAB+ via a headless
`welle.io`/`welle-cli`, shortwave through the RTL-SDR V4's built-in HF front end. The
station list is data in the mode config (`src/shared/`), so it's editable without code.
All of COMMS holds the single SDR tuner, so it displaces SIGINT (§ mode overview) — you
can't listen and scan at once. EWF only fires while actually tuned to DAB (single-tuner
limit, noted in the mode overview); the app/cell-broadcast stay the always-on warning
path.

---

## U11 — Security suite

**Requirements:**
1. Intruder alarm: nobody home + radar/camera motion at night → push + recording +
   deterrent strobe.
2. Remote voice warning to intruders via the app.
3. Radar-gated camera/recording wake (efficient perimeter watch).

**Value:** _TBD_
**Implementation:** _TBD_

---

## U12 — Intercom

**Requirements:**
1. Full-duplex (baby/room monitor).
2. One-way call ("dinner's ready").

**Value:** _TBD_
**Implementation:** _TBD_

---

## U13 — ISM sniffer

**Requirements:**
1. 433/868 MHz neighbourhood sensor net (rtl_433).
2. TPMS sniffing of passing cars.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U14 — Space & sky radio

**Requirements:**
1. NOAA weather-satellite images on overpass.
2. ISS SSTV auto-decode.
3. Meteor scatter detection (GRAVES ping), visual + audio.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U15 — APRS tracker

**Requirements:**
1. Decode and ticker passing balloons/hikers/IGates.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U16 — Radiosonde tracker

**Requirements:**
1. Track Munich-region weather-balloon launches, predict landing.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U17 — RF spectrum monitor

**Requirements:**
1. Waterfall view of nearby transmissions.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U18 — Seasonal time-lapse

**Requirements:**
1. One camera frame a day → end-of-season GIF.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U19 — Presence ghost

**Requirements:**
1. A partner's phone status/location drives a single, softly wandering pixel on the
   matrix — passive, no message or sound.

**Value:** _TBD_
**Implementation:** _TBD_

---

## U20 — Funkverkehr

**Requirements:**
1. Pager/POCSAG message monitoring.
2. Air-band voice monitoring (MUC tower/approach).

**Value:** _TBD_
**Implementation:** _TBD_

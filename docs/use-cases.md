# Use cases

The authoritative, binding list: everything here gets built. Supersedes the former
`docs/ideas.md` (rated idea pool, now folded in and removed) and README §3, which
now just points here. Global, not under `src/`, because use cases drive both the
hardware (already fixed, see `log/decisions.md`) and the software stack (`src/`).

Each entry: **Requirements** (what it must do), **Value** (why it's worth building),
**Implementation** (how, concretely). Value/Implementation are filled in as we work
through the list together — entries without them yet are marked `_TBD_`.

---

## U1 — Light at the table, automatic in the evening

**Requirements:**
1. Soft fade-in of warm-white light on presence.
2. Brightness scales with distance, not a binary on/off.

**Value:** the light comes on exactly when and where it's needed, without reaching
for a switch — and scaling with distance makes the transition feel deliberate
rather than jarring: it gently brightens as someone approaches the table instead of
snapping to full brightness the instant the radar sees anything at all, including
someone just passing the far edge of its range.

**Implementation:** the LD2410B already reports a **distance value** over UART
(moving-target and static-target distance in cm), not just a presence boolean — no
new hardware, this is unused capability already sitting in the module. ESPHome's
`ld2410` component exposes it as a sensor entity. Map distance to brightness with a
curve (e.g. >4 m off, 2-4 m ramping 20-70 %, <2 m at the table 100 % warm-white),
smoothed (exponential moving average or a debounce window) so radar jitter doesn't
flicker the light. This stays **on the ESP32**, not round-tripped through the Pi:
it's the same local control loop ESPHome already owns (radar → WLED over MQTT), just
enriched with distance instead of a boolean, and it needs to feel instant. Once the
mode architecture (`src/log/decisions.md`, 2026-07-16) is live, this is the default
*within* whichever mode leaves WLED on automatic — "away" or "party" mode override it
via the mode's own WLED preset, this behaviour doesn't fight them.

**Open before building:** the "at the table" distance threshold needs on-site
calibration once mounted (real distance from the enclosure to where people actually
sit), not a value to guess from a datasheet.

---

## U2 — Manual light control without a phone

**Requirements:**
1. Physical controls: 4 illuminated buttons + rotary encoder (on/off, scene select,
   dimming, automation pause).
2. Clap switch (2 claps) as an additional input.
3. Hand-gesture control via the camera (MediaPipe).

**Value:** _TBD_
**Implementation:** _TBD_

---

## U3 — Effect / party light

**Requirements:**
1. WLED 2D effects + strobe.
2. Scrolling-text ticker: time / temperature / next flight / welcome message.
3. Scrolling-text ticker: bird of the day.
4. Audio-reactive visualiser (mic → FFT → matrix).

**Value:** _TBD_
**Implementation:** _TBD_

---

## U4 — Environment data

**Requirements:**
1. BME280 (temperature/humidity/pressure) → MQTT → dashboard.
2. Long-term climate log in Grafana.
3. Presence usage heatmap (radar → dashboard).

**Value:** _TBD_
**Implementation:** _TBD_

---

## U5 — Aircraft reception

**Requirements:**
1. ADS-B reception via readsb/tar1090 (approach MUC, optional feed).
2. Spoken/matrix announcement on aircraft approach (airline/flight number).
3. Special alert for a rare aircraft (military/government/A380/first-seen
   registration).

**Value:** _TBD_
**Implementation:** _TBD_

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

**Requirements:**
1. FM + RDS.
2. DAB+.
3. Shortwave / world-band.
4. DAB+ Emergency Warning Functionality (EWF).

**Value:** _TBD_
**Implementation:** _TBD_

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

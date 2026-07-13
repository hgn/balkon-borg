# Use-case idea pool

Brainstormed use cases on top of the fixed **U1–U9** (README §3), collected to rate and
prioritise. **Nothing here changes the hardware design.** Fill the **Rate** column with
`skip` / `low` / `high` (or your own scale); the `high` ones can later graduate into real
U-numbers and get built.

Hardware in play: camera (CSI, Frigate/vision on the Pi), mic + speaker (USB), RTL-SDR,
LD2410B presence radar, BME280 (temp/humidity/pressure), WLED RGBW-WW 8×43 matrix,
4 buttons + encoder, button/indicator LEDs, the always-on nas-Pi and the phone app — all
over MQTT.

| # | Group | Use case | Uses | Rate |
|--:|---|---|---|---|
| 1 | Camera | Hand-pose remote: 5 fingers = light on, fist = off, thumbs-up = scene, swipe = dim; finger count = preset number | camera, WLED, speaker | |
| 2 | Camera | Wave = greeting: light pulse + "hallo" from the speaker | camera, WLED, speaker | |
| 3 | Camera | Count people at the table → auto brightness/scene (1 = reading, 4+ = party) | camera, WLED | |
| 4 | Camera | Who's here: family vs. stranger (face rec) → personal greeting/favourite scene | camera, speaker, WLED | |
| 5 | Camera | Selfie/photo countdown on the matrix → snapshot to the nas-Pi | camera, WLED, nas-Pi | |
| 6 | Camera | "Table set" detected (glasses/plates) → dinner scene + soft music | camera, WLED, speaker | |
| 7 | Camera | Thumbs up/down voting for music skip / scene | camera, speaker | |
| 8 | Security | Intruder alarm: nobody home + radar/camera motion at night → push + recording (off-site) + deterrent strobe | radar, camera, nas-Pi, WLED, app | |
| 9 | Security | Remote voice warning to intruders via the speaker (from the app) | speaker, app | |
| 10 | Security | Acoustic anomaly (glass break / footsteps) → alarm even if camera sees nothing | mic, app | |
| 11 | Security | Holiday presence simulation: pseudo-random light + occasional announcement | WLED, speaker | |
| 12 | Security | Perimeter watch: radar wakes the camera/recording only on approach (saves CPU/storage) | radar, camera | |
| 13 | Security | "Coming home" welcome: phone geofence/BT → light + "welcome home" | app, WLED, speaker | |
| 14 | Audio | Full-duplex intercom: app → nas-Pi → speaker (announce out), mic → nas-Pi → app (listen in); baby/room monitor | mic, speaker, nas-Pi, app | |
| 15 | Audio | Kitchen call: "dinner's ready" from indoors to the balcony via the app | speaker, app | |
| 16 | Audio | Local voice control (wake-word "Balkon", offline Vosk/Whisper) → light/scenes/info | mic, WLED, speaker | |
| 17 | Audio | Clap switch: 2 claps = toggle light | mic, WLED | |
| 18 | Audio | Spoken event feedback: bird name (BirdNET) / flight ("Lufthansa to Munich") via TTS | mic, SDR, speaker | |
| 19 | Audio | Morning briefing (weather/calendar) on first presence of the day | radar, speaker | |
| 20 | Audio | Evening soundscape (forest/waves), presence-triggered | radar, speaker | |
| 21 | Light | Scrolling text on the matrix: time, temperature, next flight, welcome message | WLED, BME, SDR | |
| 22 | Light | Music visualiser: mic → FFT → matrix reacts | mic, WLED | |
| 23 | Light | Sunset sync: WLED runs sunset colours at the real sunset time | WLED | |
| 24 | Light | Weather ambient: colour mirrors temperature; lightning effect on pressure drop | BME, WLED | |
| 25 | Light | Notification aura: message/call/doorbell → defined colour pulse | WLED, app | |
| 26 | Light | Flight sweep: aircraft overhead (ADS-B) → light sweep in its direction | SDR, WLED | |
| 27 | Light | Bird of the day: detected species → name as scrolling text + colour | mic, camera, WLED | |
| 28 | Light | Countdown object: egg timer, Pomodoro focus light, New Year's countdown + announcement | WLED, encoder, speaker | |
| 29 | Light | Party traffic-light: noise too high → discreet amber/red (neighbour-friendly) | mic, WLED | |
| 30 | Light | Light "follows" a person along the matrix in their walking direction | camera, WLED | |
| 31 | Light | Night sky mode: gentle starfield when nobody is present | radar, WLED | |
| 32 | SDR | Flight announcer: approach MUC → airline/flight number on the matrix + announcement | SDR, WLED, speaker | |
| 33 | SDR | Rare-aircraft alert (military/government/A380/first-seen reg) → push + special light | SDR, app, WLED | |
| 34 | SDR | 433/868 MHz sniffer (rtl_433): neighbourhood weather/sensor data as a free mini sensor net | SDR | |
| 35 | SDR | NOAA/Meteor weather-satellite images on overpass → dashboard | SDR, nas-Pi | |
| 36 | SDR | Meshtastic/LoRa RX: show or read out mesh messages | SDR, WLED, speaker | |
| 37 | SDR | POCSAG/pager ambient: nearby emergency activity as quiet info | SDR | |
| 38 | SDR | Air-band voice: listen to MUC tower/approach; "LH123 is talking to the tower" | SDR, speaker | |
| 39 | SDR | ACARS/VDL2 aircraft text messages as matrix ticker | SDR, WLED | |
| 40 | SDR | Radiosonde hunt: track Munich-region weather balloons, predict landing | SDR, nas-Pi | |
| 41 | SDR | ISS SSTV: auto-decode images from the space station when transmitting | SDR, nas-Pi | |
| 42 | SDR | DCF77 time sync (77.5 kHz, direct sampling) | SDR | |
| 43 | SDR | Spectrum monitor: "what's transmitting nearby" waterfall | SDR | |
| 44 | Env | Frost / heat warning for balcony plants (BME thresholds) → announcement/push | BME, speaker, app | |
| 45 | Env | Thunderstorm early warning: fast pressure drop → "bring cushions/laundry in" | BME, speaker | |
| 46 | Env | Ventilation hint (needs a second indoor sensor): "cooler/drier outside now" | BME | |
| 47 | Env | Grill-weather / laundry-drying index in the evening | BME | |
| 48 | Env | Plant time-lapse: one camera frame a day → growth GIF over the season | camera, nas-Pi | |
| 49 | Env | Dew-point / mould-risk from the BME trend | BME | |
| 50 | Env | Condensation warning for the enclosure itself (electronics protection) | BME | |
| 51 | Env | Long-term micro-climate log in Grafana | BME, nas-Pi | |
| 52 | Radar | Distance dimmer: closer = brighter, smooth fade-in on approach | radar, WLED | |
| 53 | Radar | Zone presence: only react in the table zone (1–2 m), ignore passers-by (3–4 m) | radar, WLED | |
| 54 | Radar | "Sits & stays" vs. "passes through": short moving = ignore, static = cosy light | radar, WLED | |
| 55 | Radar | Smart auto-off: light off only when neither moving nor static target remains | radar, WLED | |
| 56 | Radar | Nap detection: long static + late → gently dim instead of hard switch | radar, WLED | |
| 57 | Radar | Motionless-person / rough fall detection: unusually long stillness → check-in | radar, camera, speaker, app | |
| 58 | Radar | Balcony usage heatmap: log presence duration and distance over the season | radar, nas-Pi | |
| 59 | Multi | Radar + camera: radar wakes Frigate only when someone is present (saves the biggest CPU load) | radar, camera | |
| 60 | Multi | Radar + camera + mic: alarm only when multiple modalities agree (fewer false alarms) | radar, camera, mic, app | |
| 61 | Multi | SDR + camera auto plane-spotting: ADS-B position triggers a photo of the aircraft | SDR, camera, nas-Pi | |
| 62 | Multi | BME + SDR + mic: triple-confirmed thunderstorm (pressure + static + thunder) | BME, SDR, mic, speaker | |
| 63 | Multi | Camera + BME laundry watch: laundry out (vision) + rain coming (pressure) → warning | camera, BME, speaker | |
| 64 | Multi | Everything → "balcony diary": daily auto-recap (best frame, birds, flights, weather) | camera, mic, SDR, BME, nas-Pi | |
| 65 | Multi | Bird cross-validation: BirdNET (sound) + camera (image at the railing) + proof photo | mic, camera, nas-Pi | |
| 66 | Multi | BME + radar enclosure self-dry: condensation risk + nobody present → use Pi heat to stay dry | BME, radar | |
| 67 | Play | Mini-games on the matrix (Snake/Pong via the encoder) | WLED, encoder | |
| 68 | Play | Gesture DJ: hand movement steers colour/effect live | camera, WLED | |
| 69 | Play | Mood voice command ("make it cosy") → warm scene + soft music | mic, WLED, speaker | |
| 70 | Play | Wave highscore / visitor counter: how many people waved/passed today | camera, WLED | |
| 71 | SDR | **Meteor detector**: listen to the Graves space radar (143.05 MHz); a meteor's ionised trail reflects the ping (meteor scatter) → matrix renders a shooting star | SDR, WLED | **high** |
| 72 | Security | **Acoustic sonar**: speaker emits a near-ultrasonic sweep (18–20 kHz), mic measures the room echo; a large body (intruder) changes the signature → alarm. Fallback if camera/radar are blinded | mic, speaker | |
| 73 | SDR | **TPMS sniffer**: read passing cars' tyre-pressure sensors (433/315 MHz, rtl_433) → gag on the matrix ("that Audi is at 1.8 bar") | SDR, WLED | |
| 74 | Camera | **Digital shadow (anti-glare)**: camera finds the faces at the table, matrix dims exactly the pixels that would shine in their eyes, keeps the rest bright | camera, WLED | |
| 75 | Camera | **Pacifist pigeon/cat turret**: Frigate detects pigeons/foreign cats → strobe + a short raptor/dog sound → they leave, no water needed | camera, speaker, WLED | |
| 76 | Camera | **Captain's log**: button/encoder-hold starts record mode (matrix red), speak a note → saved to nas-Pi + Whisper STT → text into Nextcloud/Obsidian | camera, mic, encoder, nas-Pi | |
| 77 | Radar | **Breath pacer**: radar reads breathing micro-movements, matrix pulses with your breath then slowly slows it → you follow it (relaxation/biofeedback) | radar, WLED, speaker | |
| 78 | Ambient | **Telepresence "ghost"**: a partner's phone status/location drives a single softly glowing pixel wandering the matrix — passive "I'm here", no message or sound | app, WLED | |
| 79 | Ambient | **Urban pulse**: mic measures the city's background noise, matrix translates it into a slow organic shimmer — "breathes" faster when busy, calm late at night | mic, WLED | |
| 80 | Camera | **Flashlight spotlight**: hold your lit phone toward the camera, matrix throws a focused spotlight where you are and follows you like a stage follow-spot | camera, WLED | |
| 81 | Play | **Konami code / easter eggs**: a secret button/encoder sequence unlocks a hidden mode, light program, or inside-joke audio | encoder, buttons, WLED, speaker | |
| 82 | Env | **Invisible warning**: matrix off, but on frost (<2 °C) or heat (>35 °C) + radar sees someone approaching the door → 2 s ice-blue / deep-red flash, then off | BME, radar, WLED | |
| 83 | Meta | **Tricorder / diagnostics**: encoder press → matrix shows CPU load, WiFi/MQTT status, live radar distance, audio level — hardware debug without the phone or SSH | all sensors, WLED | |

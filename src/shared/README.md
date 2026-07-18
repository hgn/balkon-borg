# src/shared — the interface contract

The authoritative contract between all components: **borg-pi5 arbiter, ESP32, Android
app, and the capture services**. Everything that crosses a component boundary is
specified here — MQTT topics and payloads, HTTP endpoints and ports, and where media
files live. `docs/network.md` keeps the physical picture and a summary; on conflict,
this file wins. Runtime configuration (`borg.yaml`) will live here too.

Status: first clean draft (2026-07-17). Topics already referenced elsewhere in the docs
keep their names; new topics (mode state, commands, inputs, health, events) are defined
here for the first time.

---

## Conventions

- **Payloads are JSON**, UTF-8, with a schema version field `"v": 1` (bump on breaking
  change). Consumers ignore unknown fields (forward compatibility).
- **Timestamps** `ts`: ISO-8601 with offset (`2026-07-18T21:14:03+02:00`). While the
  `clock` capability is not `ok` (no NTP sync yet), timestamps are untrusted and
  timestamped persistence is gated (`pi/README.md`).
- **Units:** SI — °C, %, hPa, metres, seconds.
- **QoS:** 1 for state, commands, events; 0 for high-rate live telemetry.
- **Retained:** state, snapshots, media pointers and health are retained (a fresh client
  gets the full picture on subscribe). Commands, inputs and events are never retained.
- **Commands are fire-and-forget; the state topic is the ack.** A client sends a
  command, the arbiter applies it (or refuses) and publishes the resulting state —
  clients render state, never their own optimistic guess.
- **One writer per topic.** The arbiter owns `balkon/mode/*`, `balkon/health/*`,
  `balkon/event/*` and all `.../recent` snapshots; the ESP owns `balkon/env/*` (live),
  `balkon/presence`, `balkon/input/*`; services own their feed topics.

## MQTT — state (retained, arbiter-owned)

The four main modes run in parallel; each has its own state topic. The old single
`balkon/mode` + `/sub` + `/chan` triple is **superseded** (it could not represent four
parallel modes).

| Topic | Payload |
|---|---|
| `balkon/mode/lumen` | `{"v":1,"submode":"ticker","chan":null,"pinned":false,"since":ts}` |
| `balkon/mode/comms` | `{"v":1,"submode":"dab","chan":"dlf","pinned":true,"since":ts}` |
| `balkon/mode/sigint` | `{"v":1,"submode":"adsb","chan":null,...}` |
| `balkon/mode/sentry` | `{"v":1,"submode":"off",...}` — submodes `off·arming·armed·grace·alarm` |
| `balkon/mode/focus` | `{"v":1,"focus":"lumen"}` — which main mode the panel buttons steer |
| `balkon/state/knob` | `{"v":1,"target":"light"}` — encoder target (light ↔ audio) |

`submode` values follow the mode table in `docs/use-cases.md`; `chan` is the sub-submode
(station/frequency/preset) or `null`. SENTRY's lifecycle states (arming → armed →
grace → alarm) are submode values, so the app renders them from the same topic.

## MQTT — commands (not retained, arbiter subscribes)

| Topic | Payload | Effect |
|---|---|---|
| `balkon/cmd/mode/<main>` | `{"v":1,"submode":"disco"}` and/or `{"chan":"bayern3"}` | set submode / channel; `<main>` ∈ lumen/comms/sigint/sentry |
| `balkon/cmd/focus` | `{"v":1,"focus":"comms"}` | switch button focus |
| `balkon/cmd/brightness` | `{"v":1,"value":0..255}` | LUMEN brightness (arbiter → WLED) |
| `balkon/cmd/volume` | `{"v":1,"value":0..100}` | speaker volume |

Invalid commands (unknown submode, resource conflict the arbiter refuses) are dropped
with a log line; the unchanged state topic is the signal. Arming SENTRY via
`cmd/mode/sentry {"submode":"armed"}` starts the *arming* sequence (exit handling,
U11), it does not jump straight to armed.

## MQTT — inputs (ESP → arbiter, not retained)

| Topic | Payload |
|---|---|
| `balkon/input/button` | `{"v":1,"id":1..4,"action":"short"\|"long"}` |
| `balkon/input/encoder` | `{"v":1,"delta":±n}` or `{"v":1,"action":"push"}` |

The ESP publishes raw inputs; the arbiter interprets them against focus/mode state
(U2). Button LEDs are driven locally by the ESP from the retained mode topics.

## MQTT — telemetry and feeds

| Topic | Owner | Retained | Payload |
|---|---|---|---|
| `balkon/env/temperature` · `/humidity` · `/pressure` | ESP | no | plain number (ESPHome) |
| `balkon/env/recent` | arbiter | **yes** | `{"v":1,"samples":[{"ts":…,"t":…,"h":…,"p":…},…]}` — a few hours, 1/min |
| `balkon/presence` | ESP | no | `{"v":1,"present":bool,"distance_cm":n}` |
| `balkon/cam/events` | Frigate | no | Frigate detection events (native schema) |
| `balkon/adsb/aircraft` | arbiter | no | live aircraft of interest (from readsb) |
| `balkon/birds/detections` | BirdNET-Go | no | detection (native schema) |
| `balkon/ism/recent` · `/tpms/recent` · `/aprs/recent` · `/radiosonde/recent` · `/meteor/recent` | arbiter | **yes** | `{"v":1,"entries":[…last ~50, newest first]}` (SIGINT ring-buffer pattern) |

## MQTT — media pointers (retained, arbiter-owned)

| Topic | Payload |
|---|---|
| `balkon/noaa/image` | `{"v":1,"id":…,"ts":…,"sat":"NOAA-19","url":"http://borg-pi/media/spacesky/<id>.png"}` |
| `balkon/iss/sstv/image` | same shape |
| `balkon/timelapse/video` | `{"v":1,"id":…,"ts":…,"season":"2026","url":"http://borg-pi/media/timelapse/2026.webm"}` |

The app fetches the URL and keeps its own FIFO-50 gallery (U14); the Pi keeps a rolling
FIFO-50 in tmpfs so an offline phone can catch up.

## MQTT — health (retained, arbiter-owned)

One topic per capability plus an aggregate; this is the degraded-services interface
(stability principle, `architecture.md` §2):

| Topic | Payload |
|---|---|
| `balkon/health` | `{"v":1,"state":"ok"\|"degraded","summary":"sdr missing","ts":…}` |
| `balkon/health/<capability>` | `{"v":1,"state":"ok"\|"degraded"\|"missing"\|"disabled","detail":"…","since":ts,"last_ok":ts}` |

Capabilities (initial set): `clock` (NTP sync), `sdr`, `mic`, `speaker`, `camera`,
`esp` (mapped from ESPHome availability), `wled`, `arbiter`, and one per service
(`frigate`, `birdnet`, `readsb`, …). The **arbiter's LWT** sets
`balkon/health/arbiter` to `missing` if it dies uncleanly, so the app can tell "arbiter
down" from "all quiet". Probes re-run periodically — hardware plugged in later comes up
without restart.

## MQTT — events (not retained, arbiter-owned)

| Topic | When |
|---|---|
| `balkon/event/aircraft` | U5 trigger fired (low overflight / special) — `{"v":1,"ts":…,"kind":…,"text":…}` |
| `balkon/event/bird` | U6 bird-of-the-day / notable detection |
| `balkon/event/storm` | U9.3 pressure-drop warning |
| `balkon/event/security` | U11 confirmed person (alarm) — mirrored to push |

Events drive UI toasts and TTS; **push delivery** (ntfy on the nas-Pi + UnifiedPush,
switchable in the app) mirrors `event/security` always and other events per the app's
settings. ntfy topics: `borg-security`, `borg-events`.

## HTTP — borg-pi endpoints and ports

All LAN/WireGuard only; nothing is internet-exposed.

| Port | Service | Purpose |
|---|---|---|
| **80** | arbiter (aiohttp) | status page `/`, `GET /health.json`, `GET /media/…`, `POST /api/talkdown` |
| 1883 | Mosquitto | MQTT |
| 1984 | go2rtc | live camera: MJPEG/WebRTC stream API (U21 live view) |
| 8971 | Frigate | UI + clip archive |
| 8078 | tar1090 | ADS-B map |
| 8080 | BirdNET-Go | bird log UI |
| 8073 | OpenWebRX | spectrum waterfall (U17) |
| 19999 | Netdata | system health (host metrics) |
| — | ntfy on **nas-pi** | push server (port fixed at deployment) |

- **`POST /api/talkdown`** — body: WAV (≤ ~30 s, ≤ 5 MB), response `202 {"id":…}`; the
  arbiter plays it at talk-down priority (U21); whatever was ducked resumes.
- **Live view (U21):** the app uses go2rtc's stream URLs directly
  (`http://borg-pi:1984/api/stream.mjpeg?src=cam` or WebRTC for lower latency).
- **Status page** (port 80) renders the same data as `balkon/health/*`.

## Storage — where media lives

| What | Path on borg-pi | Served as |
|---|---|---|
| U14 NOAA/SSTV images (FIFO-50) | `/srv/borg/media/spacesky/` (**tmpfs**) | `http://borg-pi/media/spacesky/…` |
| U18 time-lapse frames | `/srv/borg/media/timelapse/frames/<season>/` | not served (raw material) |
| U18 time-lapse video | `/srv/borg/media/timelapse/<season>.webm` | `http://borg-pi/media/timelapse/…` |
| U6 bird log (SQLite) | BirdNET-Go volume `/srv/borg/birdnet/` | BirdNET-Go UI (:8080) |
| U7/U11 event clips | **nas-Pi** storage, NFS-mounted at `/srv/borg/clips/` | Frigate UI (:8971) while the unit is on |

Clips deliberately live on the nas-Pi (survivability, U7); the NFS export on the nas-Pi
is a provisioning step. Open point: browsing clips while the borg-pi is *off* (the files
are on the always-on nas-Pi; a minimal listing there is possible later if wanted).

## Broker auth (Mosquitto)

Password file + ACL, no TLS (LAN + WireGuard only):

| User | May write | May read |
|---|---|---|
| `arbiter` | everything | everything |
| `esp` | `balkon/env/*`, `balkon/presence`, `balkon/input/*`, `wled/*` | `balkon/mode/#` |
| `app` | `balkon/cmd/#` | everything |
| `svc-<name>` (per service) | its own feed topics | as needed |

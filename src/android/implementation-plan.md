# Android app implementation plan

Agreed 2026-07-17. Applies the design system in [`design/`](design/) (dark-native
violet/neon, M3 Expressive, spring motion) to the existing Provider skeleton in
[`app/`](app/). Executed stage by stage via the `android-flutter` agent (Sonnet,
autonomous); every stage ends analyze/test/build green and is reviewed + committed
before the next starts.

## Decided

- **D1 — Settings & health placement:** the design has 4 nav tabs and no
  settings/health screen. Settings opens via a **gear in the header**; an aggregate
  **status dot in the header** (green/amber/red) opens a health bottom sheet in the
  design style. No fifth tab.
- **D2 — Demo mode built in:** a `DemoSource` feeds AppState with realistic fake data
  (modes, env history, bird log, events), toggleable in settings, default **on** until
  the Pi broker exists. Keeps every screen developable and screenshotable now; stays a
  feature later.
- **D3 — Fonts bundled as assets** (Manrope + Space Grotesk, OFL): offline-first and
  deterministic; no google_fonts runtime download.
- **D4 — Charts via CustomPainter** (line + filled area, 24 points, per the design
  spec); no chart dependency.
- **D5 — Camera tab in two steps:** full UI now (SENTRY card, live placeholder with
  LIVE dot, PTT with `record` + upload to `/api/talkdown`, effect chips); **WebRTC
  wiring only once go2rtc runs on the Pi** (URLs are in the contract already).
- **Station lists (U10)** are app constants for now; they move to the Pi's config
  (retained topic) once borgd owns them.
- **D8 — The Pi owns the facts** (added 2026-07-19): world and device values belong to the
  borg-pi5 and reach the app over MQTT; the app is largely a display and keeps fallbacks,
  not authorities. Only UI preferences stay local. Constants to migrate once the Pi side
  exists: `BorgGeo.homeLat/homeLon`, `contract/stations.dart`, the radar's 50 km range,
  the condensation thresholds. See `../log/decisions.md`.
- **D6 — Visual showpieces in their leanest form** (added 2026-07-19): three ideas were
  assessed and approved, but two of them run in a cheaper variant than originally
  sketched. The ADS-B radar is drawn with `CustomPainter`, not Rive (Rive's input set is
  fixed at design time and cannot carry a varying number of aircraft blips). The
  "digital twin" is a **2D layered render** tinted live by the WLED color, not a glb
  model in a 3D viewer (a real 3D pipeline means a model export chain, a heavyweight
  or WebView-backed viewer package and a permanent GPU/battery cost for one decorative
  widget). Fragment shaders stay as sketched, but hard-gated (one-shot, reduced-motion
  aware). Each stage is developed and committed separately so a single effect can be
  reverted without touching the others.

- **D7 — Build identity from git** (added 2026-07-19): the settings show `rNNN` where
  NNN is the commit count of the built tree, plus commit date and short hash. A bigger
  number is the newer build, which is the only question a version string on a phone has
  to answer; a semantic version would have to be bumped by hand and would drift. The
  Makefile injects it (`--dart-define` + `--build-name`/`--build-number`, so the commit
  count is also the Android versionCode and an older APK cannot install over a newer
  one). A build from a dirty tree is marked `rNNN+`. Running from the IDE or in tests
  nothing is injected and the app reports itself as `dev`. `make version` prints what
  the current tree would produce.

## Stages

| Stage | Content |
|---|---|
| **E1** | Theme (`design/flutter_theme.dart` → `lib/src/theme/`), bundled fonts, app shell: header (eyebrow/wordmark/theme toggle/status dot), bottom nav, screen-enter motion, demo-mode foundation |
| **E2** | Home: 2×2 mode cards (variable typography, press scale), env stats, submode sheet, chart sheet |
| **E3** | Radio: segmented COMMS/SIGINT, preset lists (FM/DAB+/airband from U10), "now active" card with equalizer |
| **E4** | Camera: SENTRY card + switch (subtle red border), live area, PTT + chips |
| **E5** | Log: bird of the day + log list |
| **E6** | Settings/health in the design style, watch-window foreground service (6 h window, configurable interval, local notifications) |
| **E7** | Boot animation "Radar-Welle" (added 2026-07-17): logo on black, a deep-violet radar ring expands from the logo center across the screen (scaling circular container, border + blur), and the dashboard elements it sweeps over pop in staggered — as if the scan just discovered them. Fast (≤ 1.5 s), runs once per cold start. `flutter_animate` for the chained fade/scale sequences. |
| **E8** | Polish, risk-free batch (added 2026-07-17, user-approved): boot slowed to ~2 s + `start.wav` underscore (audioplayers) · systematic haptics (central helper, grammar from selectionClick to heavyImpact incl. state-echo confirmation, settings toggle) · animated env counters (tweened values, no jumps) · health-dot sonar ping (a subtle expanding, fading ring every few seconds — the dot is alive) |
| **E9** | Render-heavy batch (user-approved, wants an on-device look after): glassmorphism (BackdropFilter on sheets + bottom nav, translucent surfaces) · radar sweep (SIGINT) / sine wave (COMMS) behind the now-active card while receiving · WLED ambient glow (soft radial background in the current light color, morphing on change, off when LUMEN off) |

| **E10** | ADS-B radar (added 2026-07-19, D6): the SIGINT background sweep becomes a real plan-position indicator. Aircraft from `balkon/adsb/aircraft` are placed at their true bearing/distance around the balcony, blips fade with the sweep, the nearest gets a callsign/altitude label. `CustomPainter` + one ticker, only while the ADS-B submode is visible. Demo mode flies plausible tracks. |
| **E11** | Fragment shaders (added 2026-07-19, D6): a one-shot CRT/scanline glitch (~400 ms) over the camera view when SENTRY reports a person, and a condensation/droplet wash on the background above 85 % humidity. Native `.frag` assets via `flutter_shaders`/`FragmentProgram`, precompiled at startup, tickers bound to visibility, skipped under `disableAnimations`. |
| **E12** | *(built, then reverted 2026-07-19: the picture was not worth the vertical space it took on Home. Code is in commit 8cabc31 if it ever comes back.)* Twin-Lite: a 2D layered render of the enclosure seen from below (case shell, diffuser, LED dots), the diffuser tinted live by `wledColor` and dimmed by the WLED brightness, small state marks for camera/SENTRY/radio. Lives on Home above the mode cards; tapping opens the health sheet. Vector/`CustomPainter`, no model files. |

## Known unknowns

- **No broker/borgd yet** → demo mode; once Pi M1 stands, test against the real
  Mosquitto (demo stays an option).
- **Bird-log schema** (BirdNET-Go native) → demo data now, model adjusted at Pi M4.
- **Device testing:** build + widget tests always; device screenshots via the android
  MCP when a phone is attached — not a blocker otherwise.

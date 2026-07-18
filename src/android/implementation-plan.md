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
  (retained topic) once the arbiter owns them.

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

## Known unknowns

- **No broker/arbiter yet** → demo mode; once Pi M1 stands, test against the real
  Mosquitto (demo stays an option).
- **Bird-log schema** (BirdNET-Go native) → demo data now, model adjusted at Pi M4.
- **Device testing:** build + widget tests always; device screenshots via the android
  MCP when a phone is attached — not a blocker otherwise.

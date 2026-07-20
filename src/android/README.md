# src/android — phone app

Flutter app (`app/`), Android only. Application ID `net.jauu.balkonborg`, minSdk 33
(Android 13+). Speaks the interface contract in
[`../shared/README.md`](../shared/README.md): plain MQTT (`mqtt_client`) against the
borg-pi broker, plain HTTP for media/APK, WebRTC (`flutter_webrtc`) against go2rtc for
the U21 live view. State management: **Provider** (project decision — simple over
fancy). No TLS, no cloud, no FCM.

## Layout

| Path | Purpose |
|---|---|
| `app/` | The Flutter project (`lib/src/{contract,models,services,state,ui}/`) |
| `design/` | The UI design (from the Claude-Design session) — applied to the skeleton UI |
| `env/`, `env.sh` | Local toolchain (Java, Android SDK, Flutter) — not in git; `setup-env.sh` rebuilds it |

`lib/src/contract/topics.dart` mirrors the MQTT/HTTP contract; on contract changes,
update it together with `../shared/README.md`.

## Build

The toolchain lives in `env/` and is activated via `env.sh` (bash). The Makefile does
that for you:

```
make apk      # release APK (→ app/build/app/outputs/flutter-apk/)
make check    # flutter analyze + tests
make run      # run on a USB-connected device
```

The release APK is later published on the borg-pi at `http://borg-pi/apk/` (install =
browse + sideload; the app checks `version.json` for updates).

## Notification model (no push server)

Any app use (start or resume) arms a **6-hour watch window**
(`lib/src/services/watch_window.dart`): a `flutter_foreground_task` background isolate
periodically checks MQTT (default 30 s, configurable in Settings), diffs the retained
`balkon/event/recent` ring against the last-seen timestamp
(`lib/src/services/event_differ.dart`, unit-tested), and raises local notifications
(`flutter_local_notifications`) for new entries in enabled categories — security
defaults on. A low-priority "Borg wacht · bis HH:MM" notification with a "Beenden"
action stays visible while armed, honestly reflecting the background work. After 6 idle
hours the service stops itself; zero background work until the next app use re-arms it.
Demo mode is a no-op (no real broker) — shown as a status line in Settings rather than
firing anything.

## Status

E1–E6 done: theme, shell (header/health-dot/settings gear), all four tabs (Home/
Kamera/Radio/Log) in the design style, the settings + health screens restyled, and the
watch-window notification service. Live view (WebRTC against go2rtc) stays deferred
until go2rtc runs on the Pi (D5); talk-down (`/api/talkdown`) is wired but untested
against a real borgd. Demo mode (`DemoSource`) keeps every screen developable without
the Pi broker.

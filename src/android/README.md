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

Any app use arms a **6-hour watch window**: the app periodically checks MQTT (default
30 s, configurable in settings) and raises **local notifications** from new entries in
the retained `balkon/event/recent` ring — per-category switchable (security defaults
on). After 6 idle hours the app does zero background work until used again. The watch
window service itself is not built yet; settings and the event model are in place.

## Status

Skeleton: MQTT service (auto-reconnect), typed contract models, Provider state,
placeholder status UI (connection, modes, health, events) and a settings screen.
Next: apply the design, live view (WebRTC), talk-down, the watch-window service.

# M4c — Vision: Frigate, live view, SENTRY, talk-down

Camera recording and recognition, the security mode built on top of it, and the two things
the phone does with it: watch, and talk back.

## Build

### Frigate and go2rtc

Both as system quadlets, on the ports fixed in the contract. Frigate does detection and
event clips; go2rtc is the streaming front end the app talks to.

Camera passthrough into a container is this package's riskiest assumption. If it fights
back, say so with the actual error rather than working around it silently.

### Live view (U21)

The app's primary path is **WebRTC against go2rtc**, with MJPEG as the dumb fallback; both
URLs are already in the contract and the app is built to use them. The Flutter side is
deferred until this package makes them real, so finishing here unblocks app work.

### SENTRY (U11)

The security mode, and the only part of the system with an escalation ladder:

1. Radar reports presence (two phases), then
2. the camera must actually see a **person** (Frigate), then
3. effector: a short flash and a police-light burst on the panel, plus a short beep, then
4. recording, and a notification path to the phone.

No day/night distinction. Arming is an **explicit mode**, never automatic. While armed,
the panel pulses gently as a reminder that it is armed, because an armed system nobody
remembers arming is a system that gets disabled in anger.

Two subtleties that are easy to get wrong:

- **Armed SENTRY pins the camera to Frigate.** It cannot be scheduled away by another
  consumer while armed; that deadlock was found in review and this is the resolution.
- **Exit handling**: after a trigger, return to watching only once the scene has been
  clear once, or after roughly a minute. Otherwise one person standing in view retriggers
  the ladder forever.

### Event clips

Per the contract the clips belong on the nas-Pi over NFS, for survivability: whoever rips
the unit off the ceiling takes the SD card with them. **The user has chosen to start with
clips local on the borg-pi.** Implement local, but:

- **cap the retention** (a bounded age and a bounded size), because Frigate writing
  unbounded to an SD card is how SD cards die;
- keep the storage path configurable so switching to the NFS mount later is a config
  change and not a rewrite;
- record it in the decision log as a deliberate, temporary deviation from U7.

### Talk-down (U21)

The phone records a message and POSTs it to borgd's talk-down endpoint. Borgd
takes the speaker via the M2 mixer, plays it, and returns the speaker to whatever had it.
The app also sends an **effect parameter** to lay over the WAV; it is already in the UI and
currently goes nowhere. Define what the effects are, or reject the ones you will not
support, and say which.

## Exit criteria

- Live view works in the app over WebRTC, with MJPEG proving the fallback.
- The SENTRY ladder runs end to end: presence, person, effector, recording, notification.
- Retriggering behaves per the exit rule; arming survives an borgd restart.
- Talk-down plays on the balcony speaker and the previous audio resumes.
- Clip retention is bounded and the bound is written down.
- `make check` green.

## Cannot be verified without hardware

Camera passthrough, detection quality, and anything involving the panel or the radar. The
SENTRY ladder's *logic* is pure and must be unit-tested with a fake clock.

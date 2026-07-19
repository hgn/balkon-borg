# M4a — BirdNET-Go

Continuous bird identification from the microphone, published as detections and summarised
as the bird of the day (U6).

## Build

BirdNET-Go, ideally as a **system quadlet** with the audio socket mounted in. It is a
single Go binary, so if container audio access fights back, running it natively as a user
unit is the sanctioned fallback rather than a defeat. Decide from what actually works and
record which and why.

- Detections are published on the contract's detection topic, **one message per
  detection**, in BirdNET-Go's native payload schema.
- Its SQLite database and detection audio live under the storage path in the contract.
- **Cap the retention** of detection audio in the configuration. A good spring morning
  produces hundreds of clips, and this box runs on an SD card. Pick a bound, write it in
  the config, say what you picked.

## Schema

The app currently parses the detection payload **defensively against guessed field names**
(`BirdDetection.fromJson` in the Flutter app). This package is where the real schema gets
pinned:

1. Capture a real detection payload.
2. Write it into `../../shared/README.md` as the authoritative shape.
3. Adjust the app's model to match, in the same commit or an immediately following one.

Leaving this half-done means the phone shows an empty bird log against a working
detector, with nothing in any log to explain it.

## Microphone arbitration

The microphone is a shared resource. BirdNET listens continuously; the talk-down feature
(U21) needs the microphone on the *phone*, not here, so that does not collide. What does
collide is the user's earlier call that BirdNET runs **only when the radio is not
playing**, to keep the audio path sane. Implement that as a rule in the mixer's table from
M2, not as an ad-hoc check inside the BirdNET module.

## Health

Capability probes: container/unit running, microphone present, detections arriving at all
in the last N hours (a detector that runs but hears nothing is `degraded`, not `ok`, and
that distinction is the whole point of the health system).

## Exit criteria

- Detections appear on MQTT and in the app's bird log.
- The real payload schema is in the contract file and the app model matches it.
- Bird of the day is correct across a day boundary.
- Radio playback suppresses BirdNET listening per the mixer rule.
- A missing microphone degrades this capability only.
- `make check` green.

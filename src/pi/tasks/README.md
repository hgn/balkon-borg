# Work packages — borg-pi5

One file per package, in dependency order. Each is self-contained enough to hand to an
agent together with [`../README.md`](../README.md) (the working agreement) and
[`../../shared/README.md`](../../shared/README.md) (the wire contract).

**Read [`../README.md`](../README.md) first, every time.** It carries the conventions, the
provisioning rule ("anything you change on the Pi must be in `provision.py` first"), the
commit rules and the stability principle. A package that violates it is rejected however
well it works.

| Package | Content | Depends on |
|---|---|---|
| [m0-provisioning.md](m0-provisioning.md) | `provision.py`, base system, packages, directories, time sync, Podman, PipeWire install | — |
| [m1-broker-arbiter.md](m1-broker-arbiter.md) | Mosquitto, arbiter skeleton, mode topics, health registry, status page, deploy loop | M0 |
| [m2-audio.md](m2-audio.md) | USB sound card, PipeWire user session, Piper TTS, priority mixer | M1 |
| [m3-buffers.md](m3-buffers.md) | Ring-buffer framework, retained snapshots, env history, event ring | M1 |
| [m4a-birdnet.md](m4a-birdnet.md) | BirdNET-Go, bird detections, bird-of-day, audio arbitration against COMMS | M2, M3 |
| [m4b-sdr.md](m4b-sdr.md) | The SDR resource: readsb/ADS-B, rtl\_433, APRS, radiosonde, FM/airband listening, tuner arbitration | M2, M3 |
| [m4c-vision.md](m4c-vision.md) | Frigate, go2rtc, SENTRY logic, event clips, live view, talk-down | M1 |
| [m4d-media-http.md](m4d-media-http.md) | NOAA/SSTV images, time-lapse, APK self-hosting, media endpoints | M1 |

## Order and parallelism

M0 and M1 are strictly sequential and gate everything else. M2 and M3 are independent of
each other. The four M4 packages are independent of each other but each assumes the
foundation is real, not stubbed.

## Definition of done, for every package

**There is no Pi yet** (see [`../README.md`](../README.md)): no SSH, no execution against
hardware, and **agents do not commit**. Each package's exit criteria describe the finished
system, and are the checklist the *user* works through once the hardware arrives. What an
agent owes now:

1. `make -C src/pi check` green (mypy strict, pytest).
2. Every part of the package's exit criteria that is pure logic actually covered by tests,
   not asserted in prose.
3. A decision-log entry for anything non-trivial you settled
   ([`../../log/decisions.md`](../../log/decisions.md)).
4. An honest report: what is written, what is locally verified, which exit criteria remain
   open until the hardware exists, and what you had to compromise on.

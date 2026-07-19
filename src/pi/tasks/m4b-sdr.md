# M4b — The SDR: one tuner, many appetites

The largest package, and the one with a genuine architectural problem in it: there is
**one RTL-SDR V4** and at least six things that want it. Solve the arbitration first, then
the individual decoders become small.

## The resource problem

Consumers, all from the use cases:

| Consumer | Band | Nature |
|---|---|---|
| ADS-B (readsb) | 1090 MHz | the idle default, runs whenever nothing else claims the tuner |
| rtl\_433 (weather, smart home, tyre sensors) | 433.92 and 868.3 MHz, **hopping** | periodic observation |
| APRS | 144.8 MHz | observation |
| Radiosonde | 400-406 MHz | observation, twice a day |
| FM / DAB+ / airband / shortwave listening | various | user-initiated, wins while active |
| Spectrum view | various | user-initiated |

Rules that already exist and are not up for redesign: **ADS-B is the idle default**;
user-initiated listening displaces observation; the antenna is a manual compromise (the
mode switch retunes the tuner, not the antenna, and the system may *announce* the antenna
length to extend rather than pretending it can do it itself).

Build a **tuner resource owner** in the arbiter: a table of claims with priorities, a
current owner, clean handover (stop the previous decoder, start the next), and a return to
the idle default when a claim is released. Decoder processes are supervised: one that dies
is restarted with backoff, and repeated failures degrade the capability rather than
looping forever.

Every switch costs the previous consumer its data. Say in the health/status output what
the tuner is currently doing and why, because "why is there no ADS-B right now" must be
answerable at a glance.

## Decoders

Each is a small module that knows how to start, stop and parse one thing, feeding the ring
buffer framework from M3 and its retained snapshot topic:

- **readsb** plus tar1090 (its own quadlet, its own port). The arbiter publishes the sky
  snapshot the app's radar draws: retained, roughly once a second while ADS-B runs,
  nearest first, with distance and bearing relative to the balcony **computed here** so
  every client does not repeat the trigonometry. The exact payload is already pinned in
  the contract; the app's radar is built against it.
- **rtl\_433**, frequency-hopping between the two bands (a single band does not cover both
  the 433 and the 868 devices; this was a corrected error, do not undo it). Feeds the ISM
  and tyre-sensor rings.
- **APRS** and **radiosonde** decoders, feeding their rings. Low duty cycle.
- **Listening**: retune, route audio to the speaker via the M2 mixer. Announce the antenna
  hint on band change.

## Health

Per capability: SDR device present (`rtl_test`), the current decoder running, data arriving
within a plausible window for that feed. A radiosonde silent at noon is normal; ADS-B
silent for ten minutes in daytime Munich is not.

## Exit criteria

- The tuner arbitration is a **pure-logic, unit-tested** state machine: claims, priorities,
  preemption, release, return to idle. This is testable without an SDR and must be tested
  without one.
- With the SDR attached: ADS-B populates the app's radar with real aircraft; switching to
  FM stops it and returns to it afterwards.
- Pulling the SDR out mid-run degrades the capability, restarts nothing else, and recovers
  when it is plugged back in.
- `make check` green.

## Cannot be verified without hardware

All reception quality. Also note the RTL-SDR V4 needs librtlsdr 2.0.1 or newer: if the
distro package is older, garbage output is the symptom, and building the vendor fork
becomes a provisioning step.

# M2 — Audio chain

Give the unit a voice, and give the arbiter a way to decide who gets the speaker.

## Starting state

Raspberry Pi OS **Lite**: there is no sound server, no desktop session, no user bus beyond
what M0's linger provides. Everything here is installed and configured by provisioning
steps, not assumed.

## Build

### PipeWire in the user session

Installed by M0, configured and started here as user units under the lingering session.
The USB sound card is the sink; make the device selection **stable across reboots and
replugs** (a card index changes, a name does not). A missing card is a `missing` audio
capability, not a startup failure.

### Piper TTS

Local text-to-speech, no cloud. A voice model on disk, a small synthesis wrapper the
arbiter can call. Synthesis is not on the hot path of anything, but it must not block the
event loop either; run it off the loop and treat a failure as a degraded capability.

Announcements the system already owes: "Borg online" at boot (this package's visible
result), the antenna hint on band changes ("extend antenna to N cm", from a per-band table
in the config), and event announcements later.

### Priority mixer

The rule set for who is allowed to make noise, in one place with a pure-logic core that is
unit-tested without a sound card:

- Radio listening (COMMS) is the long-running consumer of the speaker.
- Announcements and alarms interrupt it and it resumes afterwards.
- Talk-down (U21) takes the speaker for the duration of the message and hands it back.
- BirdNET listening competes for the *microphone*, not the speaker, and is handled in M4a.

Decisions the mixer makes are data (a priority table plus current owners), not scattered
`if` statements across the codebase. When a fourth consumer shows up, it should be a table
entry.

### Health

Audio capability probes: sound card present, PipeWire responding, Piper model loadable,
synthesis actually producing samples. Report each honestly. A Pi with no speaker attached
must still boot and run everything else.

## Exit criteria

- The unit says "Borg online" from the speaker after a cold boot, without a login.
- Unplugging the sound card degrades the audio capability and leaves everything else
  running; replugging it recovers without a restart.
- The mixer's priority decisions are unit-tested without hardware.
- `make check` green.

## Cannot be verified without hardware

PipeWire against the real USB card, and whether the speaker is loud enough outdoors. Both
need the physical unit. Do not stub the sound server out and report the package as
verified.

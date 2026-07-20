# src/pi — borg-pi5 software

Everything that runs on the borg-pi5, plus the tooling that puts it there. This file is
the **working agreement**: an agent that reads only this file and the task package it was
given has enough to work correctly. Read it fully before writing code.

- **How the Pi is set up and what it is built from:** [`setup.md`](setup.md) — the
  manual first steps (image, WiFi, SSH) and the technology in detail: Podman quadlets,
  borgd, PipeWire, time sync, health, storage, deployment.
- **What is being built:** [`implementation-plan.md`](implementation-plan.md) (decided
  2026-07-17: Python provisioning tool, system quadlets + user-session borgd, pydantic
  config, health registry, milestones M0-M4+).
- **The work packages:** [`tasks/`](tasks/) — one file per package, in order. Each names
  its own exit criteria.
- **Why things are the way they are:** [`../log/decisions.md`](../log/decisions.md). Check
  it before reopening a settled question, and append to it when you settle a new one.
- **The wire contract (authoritative):** [`../shared/README.md`](../shared/README.md).
  MQTT topics, payloads, HTTP endpoints, storage paths. The Android app is already built
  against it. Changing it means changing two sides plus that file, in one commit, with a
  decision-log entry.

## There is no Pi yet

**The hardware has not been delivered.** No agent working on these packages has SSH, a
running host, or any way to execute what it writes against real hardware. Everything is
written blind, verified locally (`mypy strict`, `pytest`), and run for the first time by
the user once the Pi 5 arrives.

Three consequences, and they shape how the code has to look:

- **No agent commits.** Write the files, report what you did, stop. The user reviews and
  commits.
- **A script you cannot run is a script you have to reason about.** Probes, error paths
  and messages carry the weight here that a quick test run would otherwise carry. Assume
  every step will first execute in front of a person holding a new Pi, and make the
  failure output good enough for that moment.
- **Pure logic is the part you can actually verify**, so put as much of the system there
  as honestly fits: the mode state machine, the tuner arbitration, the ring buffers, the
  mixer priorities, the health registry, the SENTRY ladder. Test those properly. Anything
  that only exists inside an SSH call is untested by construction, so keep that layer thin.

Do not report a package as verified on hardware. Report it as written and locally checked,
and name what is still unproven.

## The device in one paragraph

A multifunction unit hanging under a balcony ceiling. The **borg-pi5** inside it is the
hub: camera (CSI), microphone and speaker (USB), an RTL-SDR V4 (USB), and an MQTT broker
that everything talks over. An **ESP32** running ESPHome is the front panel (buttons,
rotary encoder, presence radar, environment sensors) and publishes raw input. A **WLED
controller** drives the light panel. A separate always-on **nas-Pi5** handles remote
access. The borg-pi5 is powered on only when needed, not 24/7, and it must come up
correctly from cold with no clock, no network guarantees and possibly no hardware
attached. Full picture: [`../../README.md`](../../README.md), use cases in
[`../../docs/use-cases.md`](../../docs/use-cases.md), system view in
[`../architecture.md`](../architecture.md).

## The Pi owns the facts

The borg-pi5 is the master of this system. Every fact about the world or the device
lives here and travels to clients over MQTT: home coordinates, distance and altitude
thresholds, station lists, detection limits, retention rules. The phone app is largely a
display. It may offer to change such a value, but it does so by sending a command; it
never becomes the owner.

Clients are allowed a **fallback** for the moment before the Pi has answered, never an
authority. Only pure UI preferences (sounds, haptics, effects, theme, display name) are
genuinely theirs, because those differ per person.

So when a service needs a tunable, put it in `../shared/borg.yaml` and, where it is
useful to change at runtime, expose it over MQTT. Do not leave it to the clients to
each carry their own copy.

## The one principle that outranks the others

**The system runs with any subset of hardware present.** An unplugged SDR, a dead
microphone, a missing camera, an ESP that never boots: none of it blocks startup, none of
it raises past its own module, none of it takes another capability down with it. The
affected capability is *reported* (health registry, retained MQTT, status page) and
everything else stays usable. Failures are messages, not exceptions.

Write code that way from the first line. It is much harder to retrofit than to build in,
and it is the difference between a device that degrades and one that is simply dead one
morning for a reason nobody can see.

## Target host

| | |
|---|---|
| Host | `borg-pi` (resolved by the Fritz!Box; do not hardcode an IP) |
| OS | Raspberry Pi OS **Lite**, 64-bit. No desktop, no PipeWire preinstalled |
| User | `pfeifer` (the account created during imaging), `linger` enabled for user units |
| Access | SSH with key auth |
| Python | 3.12+ expected; M0 verifies and pins the actual version here |

Because the image is Lite, **PipeWire and everything the audio chain needs is an explicit
provisioning step**. Do not assume a session bus, a sound server or a desktop exists.

## Provisioning model

**Manual and out of scope:** flashing the image, WiFi, enabling SSH. The user does this
by hand on a fresh SD card.

**Everything after that is scripted**, driven from the control machine (this repo), never
typed by hand on the Pi. Two things this buys: rebuilding the Pi is re-running a script
rather than remembering a sequence, and after an SD card dies the recovery is one manual
image flash plus one script run.

This gives the hard rule for agents:

> **Everything the Pi needs must be expressed in `provision.py`.** Nothing is ever fixed
> by hand on the box: a state the script does not reproduce is a state nobody can rebuild,
> and the next SD failure loses it. This holds later, when there is a Pi to log into, and
> it holds now, when writing the script is the only thing anyone can do anyway.

Every provisioning step is **idempotent**: it probes the current state and does nothing if
it is already correct. Re-running the whole thing is a no-op and must stay a no-op.

## Layout

```
src/pi/
  provision.py         provisioning tool (control machine, Python, stdlib only)
  tests/               its tests (pytest)
  borgd/             borgd (Go, one static binary)
    contract.go        topics and payload envelopes, mirroring shared/README.md
    modes.go           mode state machine, incl. the single-tuner rule
    health.go          capability registry
    probes.go          the only code that touches hardware
    status.go          the status page and health.json
    main.go            MQTT + HTTP wiring
  config/              systemd units, mosquitto.conf, udev rules, timesyncd.conf
  quadlets/            *.container for the third-party services
  tasks/               the work packages
```

**Two languages on purpose** (decided 2026-07-20, see the decision log): borgd is
Go because it ships as one static binary with no runtime to maintain on the Pi, and
`provision.py` is Python because it runs on the control machine, needs no build step,
and must still work when everything else is broken.

`../shared/borg.yaml` is the runtime configuration, shared with the other components.

## Conventions (these are not suggestions)

Everything below applies to every file in this directory. They come from the project's
global conventions; an agent working here does not need to look them up elsewhere.

### Language and text

- **All code, identifiers, comments, documentation, log output and commit messages are
  English.** (Chat with the user is German; nothing written to disk is.)
- Prose reads like a human wrote it. No em-dashes or en-dashes as punctuation, no
  marketing register, no "delve", "seamless", "robust solution". Use commas, parentheses,
  colons or two sentences. Compound hyphens inside words are fine.
- UTF-8, LF, final newline, no trailing whitespace, **100 columns**.
- Comment the non-obvious: *why*, not *what*. Prefer a name that needs no comment. No
  banner or decoration comments.

### Filenames

Separator is `-`, **never `_`**, for every file type: `ring-buffer.py`, `mosquitto.conf`,
`m0-provisioning.md`. The single exception is importable Python modules and packages, which
use one lowercase word (`buffers/rings.py`); fall back to `_` only if one word is truly
impossible.

### Go (borgd)

- `gofmt` decides formatting; run `make fmt`. `go vet` must be clean.
- Errors are values and are wrapped with context (`fmt.Errorf("...: %w", err)`); the
  message says what was being attempted, because it will be read from a journal by
  someone who was not there.
- Diagnostics to stderr with `fmt.Fprintf(os.Stderr, ...)`, results to stdout. **No
  logging framework**: systemd captures both streams and `journalctl` is the log.
- Standard library first. The three dependencies that earned their place are
  `paho.mqtt.golang`, `yaml.v3` and nothing else; `net/http` covers the rest.
- Anything that touches hardware or the network goes behind a small function type
  (see `probes.go`'s `commandRunner`), so the logic around it stays testable with no
  hardware present. That is not architecture for its own sake: there is no Pi to test
  against, so what is not injectable is not verified.
- Tests are `*_test.go` next to the code, table-driven where it helps. A test that
  needs a device does not belong here.

### Python (the provisioning tool)

- Shebang `#!/usr/bin/env python3` on anything executable, and `chmod +x` it.
- Target **3.12+**. **Type hints are mandatory**, checked with **mypy strict**.
- Results to **stdout**, diagnostics and errors to **stderr**
  (`print(..., file=sys.stderr)`). **No `logging` module**, no logging framework. On the
  Pi, systemd captures both streams; that is the log.
- `pathlib` over `os.path`, f-strings, `argparse` for CLIs.
- `def main() -> int:` returning the exit code, guarded by
  `if __name__ == "__main__": raise SystemExit(main())`.
- Prefer the standard library. A third-party dependency has to earn its place. The ones
  already earned: `aiomqtt`, `aiohttp`, `PyYAML`, `pydantic` (config validation, so a typo
  in `borg.yaml` fails at startup rather than at 3 a.m.). **`provision.py` itself is
  stdlib only** — it must run on a bare control machine with no venv.
- Tests with **pytest**. Every pure-logic module (state machine, ring buffer, mixer
  decisions, health registry, config parsing) is testable without hardware and must be
  tested that way.
- Deterministic output: fix seeds, sort collections before emitting. Measure elapsed time
  with `time.monotonic()`, never wall-clock. When parsing foreign tool output, force
  `LC_ALL=C` so locale cannot shift number, date or sort formats.

### CLI and program output

- English, compact, modern. No emoji.
- Meaningful exit codes: 0 success, non-zero a specific failure.
- Provide `--help`. `provision.py` additionally provides `--dry-run` and `--only <step>`.
- `\r` progress only when stderr is a TTY (`isatty`). Respect `NO_COLOR`; colourise only
  on a TTY.
- Timestamps compact and modern, not verbose.

### Make

A top-level `Makefile` is the entry point for everything. Default goal `all`, `.PHONY` for
non-file targets, `.DELETE_ON_ERROR`, parallel-safe, and a `help` target listing what
exists. Standard targets: `all`, `clean`, `distclean`. This directory adds `provision`,
`deploy`, `logs`, `status`, `shell`, `check` (mypy strict + pytest).

### Shell

Shell only for trivial glue under ten lines. Anything larger is a Python script. No
`curl | sudo bash`, no unprompted `sudo`, no `rm -rf` in a script that a human did not
explicitly ask for.

### Git

- Linux kernel commit style: subject `subsystem: imperative summary`, around 50 chars and
  at most 75, no trailing period. Blank line. Body wrapped at 72 columns explaining **why**,
  not how.
- `Signed-off-by:` trailer on every commit.
- **Off-hours timestamps.** Commits must never look like they happened during working
  hours (Mon-Fri 07:00-21:00 local). On a weekday inside that window, set both
  `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` to an evening time (21:00 onward) on the
  *same* calendar day, and strictly later than the previous commit
  (`git log -1 --format=%cI`); if the computed time is not later, use the previous
  commit's time plus one second. Weekends and evenings commit normally. Never rewrite
  already pushed commits for this.

  ```
  GIT_AUTHOR_DATE="2026-07-20T21:14:03+02:00" \
  GIT_COMMITTER_DATE="2026-07-20T21:14:03+02:00" \
  git commit -s -m "pi: ..."
  ```

### Decision log

As soon as a non-trivial decision is made (stack choice, protocol, data contract,
scheduling or priority rule, a rejected alternative), **append a dated entry at the top of
[`../log/decisions.md`](../log/decisions.md)**, in the format that file already uses.
Record *why*, and which alternative was rejected for which reason. Do not log what the
code already says. This log is the project's memory: it is what stops a settled question
from being reopened in three months.

Hardware decisions go to `../../log/decisions.md` instead. Software decisions never go
there.

## Safety and scope

- **Never touch the Android app's `android/app/src/main/res/`** or any user-supplied asset.
- Destructive commands (`rm -rf`, `dd`, `mkfs`, `git push --force`) are not run
  unprompted. Show what would happen first; dry-run `rsync` and `find -delete`.
- The Pi is on a protected LAN and is not internet-facing. There is deliberately **no
  TLS** anywhere in this system (see the decision log): longevity and the absence of
  certificate infrastructure beat transport security for a LAN device that the user must
  still be able to repair in five years. Do not add HTTPS, do not add certificate
  handling, do not propose it.
- Broker credentials live in `../shared/borg.yaml`, checked in. That is the user's call
  for this repo; do not invent a second secrets mechanism.

## Verification

What is available now:

```
make -C src/pi check   # mypy strict + pytest, no hardware needed
```

What the user runs later, once the Pi exists:

```
make -C src/pi provision   # must be a no-op on a second run
make -C src/pi deploy
```

Report honestly. If tests fail, say so and show the output. If a step was skipped, say
that. A package that "works except for" is not done, it is a package with a known defect,
and the next agent needs to know which. Since nothing here can be run against hardware,
the report matters more than usual: it is the only description of what is actually solid.

## What cannot be verified at all right now

Everything touching hardware: SDR reception, camera passthrough into a container, PipeWire
against a USB sound card, container device access in general, and anything involving the
ESP32 or the WLED panel. On top of that, for as long as the Pi is missing, so is every
integration path: the broker, the units, the deploy loop and the provisioning steps
themselves have never executed.

Each package names what it depends on. Never stub the hardware out of a test and call the
result verified.

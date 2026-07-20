# borg-pi5 setup and technology

Two halves. The first is what you do by hand on a fresh SD card, the one part of this
project that is not scripted. The second is the technology the scripted part is built
from, in enough detail that nobody has to guess which tool does what or why it was
picked over the obvious alternative.

The working rules for anyone writing code here are in [`README.md`](README.md); the work
packages are in [`tasks/`](tasks/).

---

# Part 1: the manual part

Everything here happens once per SD card. It ends the moment the Pi answers over SSH;
from there `provision.py` takes over.

## What you need

- Raspberry Pi 5, 8 GB, plus the Active Cooler (mandatory, see
  [`../../docs/build-notes.md`](../../docs/build-notes.md))
- A microSD card, A2-rated, 64 GB
- The official 27 W USB-C supply for the bench setup (in the enclosure the Pi is fed 5 V
  over GPIO from the LRS, but you are not there yet)
- A machine with `rpi-imager` and your SSH key

## Step 1: write the image

Raspberry Pi OS **Lite**, 64-bit. Lite on purpose: this box never has a screen, and a
desktop session would cost RAM that Frigate wants.

In `rpi-imager`, open the settings gear **before** writing and fill in:

| Field | Value |
|---|---|
| Hostname | `borg-pi` |
| Username | `pfeifer` |
| Password | your choice (SSH key is what you will actually use) |
| WiFi SSID / password | your network, country `DE` |
| Locale / timezone | `Europe/Berlin`, keyboard `de` |
| SSH | enabled, **public-key only**, paste your `~/.ssh/id_*.pub` |

Setting all of this in the imager is what keeps this step to one screen. Doing it
afterwards by hand means editing files on the boot partition and is a good way to spend
an evening on a typo.

## Step 2: first boot

Insert the card, attach the cooler's fan connector, power up, wait a minute. The Pi
joins the WiFi on its own.

```
ping borg-pi
ssh pfeifer@borg-pi
```

If the name does not resolve, look in the Fritz!Box under the connected devices; the Pi
registers its hostname over DHCP. Prefer fixing it there (assign the name, optionally a
static lease) over hardcoding an IP anywhere, because the name is what the app, the
contract and the scripts all use.

## Step 3: hand over to the script

That is the end of the manual part. From your machine:

```
make -C src/pi provision
```

It is idempotent: run it again any time, and every step that is already true says so and
does nothing. If it fails, it names the step and what it saw.

## Changing the broker password

`broker.password` in `src/shared/borg.yaml` is one pre-shared secret for the arbiter,
the app and the ESP. To change it:

```
./provision.py --only mosquitto-passwd
```

The plain provisioning run will not notice on its own: the hashes in the broker's
password file are salted, so they differ on every run and cannot be compared against
the config. The step therefore only checks *which accounts* exist, and a changed
password needs the explicit call above. Then enter the new value in the Android app's
settings and in the ESP config.

## After an SD card dies

Repeat steps 1 to 3. That is the whole recovery procedure, and it is the reason the
manual part is kept this small.

---

# Part 2: the technology

## Overview

```
control machine (this repo)                     borg-pi
─────────────────────────────                   ───────────────────────────────────
provision.py ── ssh/rsync ──────────────────▶   system units + config
go build (arm64) + rsync ───────────────────▶   /srv/borg/app/borg-arbiter

                                                systemd (system)
                                                  └─ Podman quadlets
                                                       mosquitto, frigate, go2rtc,
                                                       readsb/tar1090, birdnet-go
                                                systemd (user, lingering)
                                                  ├─ borg-arbiter (Go: MQTT + HTTP)
                                                  └─ pipewire + wireplumber
```

The split is deliberate: containers need device access and run as system units, while
audio needs a user session and so does the arbiter that drives it.

## Provisioning: plain Python over SSH

`provision.py` runs on the control machine, uses **only the standard library**, and
drives OpenSSH and `rsync` through `subprocess`. It must work on a bare machine with no
virtualenv, because the day you need it most is the day the SD card died.

Structure: a declarative list of steps, each with a **probe** and an **action**. The
probe answers "is this already true?" and the action only runs when it is not. That is
what makes a re-run a no-op instead of a gamble. Flags: `--list`, `--dry-run`,
`--only <step>`, `--host`.

One SSH **ControlMaster** connection is reused across all steps (`-o ControlMaster=auto
-o ControlPersist=60s` against a socket in a temp dir), because forty steps each paying
a fresh handshake turns a ten-second run into a minute.

**Why not Ansible:** it would bring a whole runtime and an inventory for nine steps
against one host, and it would still need custom modules for the interesting parts. A
single file that you can read top to bottom wins here. This was settled on 2026-07-17,
see the decision log.

## Container runtime: Podman with quadlets

Third-party services (Mosquitto, Frigate, go2rtc, readsb/tar1090, BirdNET-Go) run as
containers under **Podman**, described as **quadlets**: a `.container` file that systemd
generates a real unit from at boot.

```ini
# /etc/containers/systemd/mosquitto.container
[Unit]
Description=Mosquitto MQTT broker

[Container]
Image=docker.io/library/eclipse-mosquitto:2
PublishPort=1883:1883
Volume=/srv/borg/mosquitto/config:/mosquitto/config:Z
Volume=/srv/borg/mosquitto/data:/mosquitto/data:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
```

Why this shape:

- **Podman over Docker:** no daemon, and it is what Raspberry Pi OS packages. A crashed
  daemon taking every service with it is a failure mode this box does not need.
- **Quadlets over `podman generate systemd`:** the generated-unit approach produces files
  you then have to keep in sync by hand. A quadlet *is* the description; systemd
  regenerates the unit on every reload. It is also the path Podman actually maintains.
- **Quadlets over docker-compose:** compose adds a second orchestrator on top of the one
  the system already has. systemd already does dependencies, restarts, logging and boot
  ordering.
- **System (root) quadlets, not rootless:** device passthrough for the SDR, the camera
  and the sound card is the whole point, and rootless turns each of those into an
  exercise. The box is protected, not internet-facing, and this was the user's explicit
  call (2026-07-17). Rootless stays available per service if it is ever free.

## The arbiter: one Go binary

The application logic is a single statically linked Go binary running as a **user**
systemd unit with `loginctl enable-linger`, so it starts at boot without a login.

Go rather than Python, decided 2026-07-20. The deciding argument is not speed (this
process waits on MQTT messages and timers, and would bore either language) but
deployment and longevity: `GOOS=linux GOARCH=arm64 go build` produces one file that
rsync puts on the Pi, with no interpreter, no virtualenv, no pip and no four runtime
dependencies to keep alive across distribution upgrades. A binary built today still
runs in five years; a venv rots. BirdNET-Go on the same box is Go for similar reasons.

- **MQTT**: `github.com/eclipse/paho.mqtt.golang`, with auto-reconnect and a **last
  will** so a dead arbiter is visible rather than silently stale.
- **HTTP**: `net/http` from the standard library. Server-rendered HTML, no build step,
  no framework. The status page has to still work in five years from a phone browser
  in the garden.
- **Config**: `gopkg.in/yaml.v3` with `KnownFields(true)`, so an unknown key is an
  error. A typo fails at startup naming the field instead of turning into odd
  behaviour at three in the morning.

Files rather than packages while it is small: `contract.go` (topics and envelopes),
`modes.go` (the state machine and the single-tuner rule), `health.go` (capability
registry), `probes.go` (the only code that touches hardware), `status.go` (the page),
`main.go` (the wiring). Packages appear when one of them grows enough to earn the
import.

**`provision.py` stays Python.** It runs on the control machine, not the Pi, needs no
build step and only the standard library. A recovery tool that must be compiled before
it can rescue a dead Pi would be a step backwards.

**Port 80 from a user unit** comes from one sysctl, `net.ipv4.ip_unprivileged_port_start=80`,
rather than capabilities or a reverse proxy. One line, no extra moving part.

## Audio: PipeWire in the user session

Pi OS Lite ships no sound server, so PipeWire and WirePlumber are installed and enabled
as user services by a provisioning step. The USB card is selected **by name**, never by
card index, because an index changes when something is replugged.

**Piper** does text-to-speech locally, from a voice model on disk (German,
`de_DE-thorsten-medium`). No cloud: a device that announces "Borg online" must not
depend on someone's API being up, and the announcements are short and fixed enough that
local synthesis is plainly good enough. Neither Piper nor the voice is packaged by the
distribution, so provisioning downloads both; the URLs are constants in `provision.py`
and are the kind of thing that rots, so the step names the URL when a download fails.

Playback is two small processes rather than a temporary file: `piper` writes a wav to
stdout, `pw-play` reads it from stdin.

The **priority mixer** is a table, not scattered conditionals: radio 10, announcement
50, talk-down 60, alarm 100. Higher wins, equal priority lets the incumbent finish
(swapping one announcement for another mid-sentence is just noise), and only the radio
is *resumable*: it comes back on its own after an interruption, while an announcement
that got cut off by an alarm is stale by the time the alarm is done. Switching COMMS off
while something talks over it drops the radio from the resume list, so it does not
reappear afterwards. When a fourth consumer shows up it should be a row in that table.

The microphone has one rule of its own: BirdNET listens unless the radio is playing.

## Time: NTP with a gate

The Pi has no RTC and boots cold, so at power-on its clock is wrong. Timestamps here are
load-bearing (bird log, events, time-lapse), so:

- `systemd-timesyncd` against a **pool**, retrying until it succeeds;
- sync state is exposed as a capability, and **timestamped persistence is gated on it**.

A gap in the bird log is a gap. A bird log full of 1970 is corruption that outlives the
misconfiguration that caused it.

## Health: probe, state, reason, since

Every capability (SDR, mic, speaker, camera, clock, ESP data, each container) has a probe
and a state of `ok`, `degraded`, `missing` or `disabled`, plus a reason and a `since`
timestamp. Published as retained MQTT and rendered on the status page.

Retained matters: a phone that connects for thirty seconds every half hour has to get the
full picture on subscribe rather than waiting for the next change. Probes are periodic,
so plugging the SDR in later brings it back without a restart, and a probe that throws
is a degraded capability rather than a crashed arbiter.

## Storage

`/srv/borg/` with per-service subdirectories. The volatile media directory (NOAA and SSTV
images) is a **tmpfs**: the Pi is not an archive, the phone keeps the permanent copy, and
writing a rolling fifty images to an SD card would be pointless wear.

Frigate's event clips are the one place with a real bound to set. They belong on the
nas-Pi over NFS (survivability, U7) and start local by the user's call, so retention is
capped by age and size. Unbounded recording onto an SD card is how SD cards die.

## Deployment

`make deploy` rsyncs `src/pi/` and `src/shared/` to the host and restarts the units.
**No git on the Pi**: the repo is the single source of truth and the Pi is a target host,
so there is never a question of which side is ahead. `make logs`, `make status` and
`make shell` are thin wrappers over `journalctl` and `ssh`.

## What is deliberately absent

- **No TLS.** LAN plus WireGuard, no certificate infrastructure that expires and bricks
  the unit in three years. Settled, not up for revisiting.
- **No logging framework.** Results to stdout, diagnostics to stderr, and systemd
  captures both. `journalctl --user -u borg-arbiter` is the log.
- **No database** beyond what BirdNET-Go brings for itself. Ring buffers in RAM plus
  retained MQTT snapshots cover what the clients need.
- **No frontend build.** The status page is server-rendered HTML.

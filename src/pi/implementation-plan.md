# borg-pi5 implementation plan

The agreed plan for building the Pi software, decided 2026-07-17 (chat review of the
draft plan). What is being built: the borg-pi5 foundation — provisioning tool, Mosquitto,
arbiter skeleton, health system, audio chain — such that the Pi runs **standalone without
the ESP or any sensor**, and every input source and every piece of hardware is optional.

Riskiest assumption: container device passthrough (SDR, camera, mic) behaves; mitigated
by not insisting on rootless (see D2).

## Decided

**D1 — Provisioning: own Python tool, no Ansible.** A single `provision.py` on the
control machine (stdlib only: `subprocess` + OpenSSH/`rsync`, ControlMaster for speed).
Declarative step list (packages, config copies, unit enablement), **idempotent** (each
step probes current state; re-run is a no-op), `--only <step>`, `--dry-run`. The manual
part stays exactly: flash image, WiFi, SSH (`README.md` provisioning model).

**D2 — Pragmatic privileges, not rootless-purism.** The box is uncritical, protected,
not internet-facing (user's call). So: **system quadlets (root)** for containers — device
access without workarounds. The **arbiter + audio run in the user session** (PipeWire
requires a user session; linger enabled). Port 80 for the status page via the
`net.ipv4.ip_unprivileged_port_start=80` sysctl (one provisioning step) rather than
capability gymnastics. Rootless remains a per-service option if it's ever free.

**D3 — Arbiter: one process, modular inside.** No microservices; the coupling (mode
state ↔ mixer ↔ resource table) is central by design. Areas: mode state machine, audio
mixer, ring buffers + retained snapshots, health registry, HTTP (status page, image
serving U14/U18, talk-down upload U21).

**D3a — Written in Go** (revised 2026-07-20, superseding the asyncio/`aiomqtt` plan):
one statically linked binary, cross-compiled `GOOS=linux GOARCH=arm64` and rsynced to
the Pi. The argument is not speed (this process waits on messages and timers) but that
there is no runtime to install or maintain on the box: no venv, no pip, no dependency
drift across distribution upgrades. `paho.mqtt.golang`, `net/http`, `yaml.v3`.

**D4 — Python stays for provisioning only:** `provision.py` runs on the *control
machine*, standard library only, no build step, checked with mypy strict and pytest. A
recovery tool that must be compiled before it can rescue a dead Pi would be a step
backwards, which is where the language boundary sits.

**D5 — Deploy loop: rsync push, no git on the Pi.** `make deploy` (rsync `src/pi/` +
`src/shared/` → Pi, reload units, restart), `make logs` / `make status` / `make shell`.
The repo is the single source of truth; the Pi is a target host.

## Stability principle (user's Grundsatz)

**The system runs robustly with any subset of hardware present.** Missing or broken
hardware (SDR unplugged, mic dead, camera absent) never blocks startup and never crashes
anything — the affected capability is reported and everything else stays usable. If
hardware and kernel are fine, everything is usable.

Concretely, the arbiter keeps a **health registry**:

- Every capability (SDR, mic, camera, speaker, ESP-sourced data, each container service)
  has a **probe** (device present? service running? data flowing?) and a state:
  `ok / degraded / missing / disabled`.
- Published as **retained MQTT** — `balkon/health/<capability>` per item plus an
  aggregate `balkon/health` — so the app shows system health immediately on connect.
- Rendered as a **central status page at `http://borg-pi:80`** (the arbiter's aiohttp) —
  one glance: what's up, what's missing, why, since when.
- **Periodic re-probe**: plugging the SDR in later brings its capability up without a
  restart. Failures are messages, not exceptions.

## Milestones

| M | Content | Standalone-testable |
|---|---|---|
| **M0** | `provision.py` + base steps: packages, NTP pool + sync gate, linger, Podman, directory layout, udev groups, port-80 sysctl | re-run = no-op |
| **M1** | Mosquitto quadlet (+ auth) · arbiter skeleton: retained `balkon/mode/*` defaults, **health registry + status page (:80)**, user unit · deploy loop | `mosquitto_sub`, browser |
| | *(M0 and M1 written 2026-07-20, untested against hardware: no Pi yet)* |
| **M2** | Audio chain: USB card, PipeWire, Piper, mixer skeleton → "Borg online" on boot; audio capability health | speaker only |
| **M3** | Ring-buffer framework + retained snapshots (`env/recent`, …) — ESP topics as optional source, empty is fine | fake publisher |
| **M4+** | Services by value, one per step, each with its health probe: BirdNET-Go → readsb/tar1090 → Frigate+go2rtc → SIGINT extras → U14/U18 → APK hosting (`/apk/`) | per hardware |

## Known unknowns (defaults + pivot signals)

- **Pi OS / Python version on the real image** → assume current 64-bit (Py 3.13); M0
  verifies and pins in the README. Bookworm/3.11 → lower the guard or reflash.
- **RTL-SDR V4 driver** (needs librtlsdr ≥ 2.0.1) → distro package; `rtl_test` as a
  provisioning check. Garbage RX → build the rtl-sdr-blog fork as a provisioning step.
- **BirdNET-Go container ↔ PipeWire** → quadlet with socket mount; if audio access
  fights back, BirdNET-Go is a single Go binary and runs natively as a user unit.
- **Mode→service settings mapping** (§9) → not designed up front; M1 starts minimal
  (mode topics + §7 defaults), the config schema grows per service. Redesign signal:
  three services copying the same pattern.

## Layout

`src/pi/`: `provision.py` · `arbiter/` (`modes/`, `audio/`, `buffers/`, `health/`,
`http/`, `main.py`) · `quadlets/*.container` · `config/` (systemd units, mosquitto.conf,
udev rules, timesyncd.conf) · `pyproject.toml`. First real file in `src/shared/`:
`borg.yaml`. Makefile targets: `deploy`, `logs`, `status`, `shell`, `provision`, `check`
(mypy strict + pytest). Pure-logic modules (state machine, ring buffer, mixer decisions,
health registry) are testable without hardware.

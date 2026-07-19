# M0 — Provisioning tool and base system

Bring a freshly imaged Pi from "answers over SSH" to "ready to run the arbiter", entirely
from a script, repeatably.

## Starting state

The user has flashed Raspberry Pi OS **Lite 64-bit**, configured WiFi and enabled SSH by
hand. The host answers as `borg-pi`, user `pfeifer`, key auth. Nothing else has been
touched. That is the only manual step in the entire project; everything you build here
takes over from that point.

## Build

### `provision.py`

A single tool on the control machine. **Stdlib only** (`subprocess`, `pathlib`,
`argparse`, `shlex`) driving OpenSSH and `rsync`. It must run on a bare machine with no
venv and no install step.

- A **declarative step list**: each step has a name, a probe ("is this already true?") and
  an action. The probe runs first; if it passes, the step prints one line and does
  nothing. **Idempotence is the property this whole package is judged on.**
- `--only <step>` to run a single step, `--list` to show them, `--dry-run` to print what
  would happen without touching the host, `--host` to override the target.
- One SSH **ControlMaster** connection reused across all steps, otherwise a 40-step run
  spends most of its time in handshakes.
- Output: step results to stdout, diagnostics to stderr, non-zero exit on the first
  failure with the failing step named. Compact, one line per step in the normal case.
- A failed step must say what it tried, what it got back, and what a human should look at.
  This tool will be read at its least convenient moment, after an SD card died.

### Steps to implement

1. **Preflight**: reachable over SSH, expected user, expected architecture, OS release
   readable. Verify the Python version on the host and **write the real value into
   `../README.md`'s host table** as part of this package.
2. **Packages** via apt: build essentials as needed, `podman`, `rsync`, `python3-venv`,
   the RTL-SDR userspace, PipeWire and its session manager, NFS client bits if used later.
   Pin nothing that does not need pinning; the box tracks the distro.
3. **Time sync.** The Pi has no RTC and boots cold, but timestamps are load-bearing (bird
   log, events). Configure `systemd-timesyncd` against a **pool** of servers and keep
   retrying until sync succeeds. Expose "time is synced" as something the arbiter can
   read, because timestamped writes are gated on it (see M3). Never persist a record
   stamped with an unsynced clock.
4. **Directory layout** under `/srv/borg/` per the contract's storage map, with the right
   ownership, plus the tmpfs mount for the volatile media directory.
5. **User session**: `loginctl enable-linger pfeifer` so the arbiter and audio survive
   without a login.
6. **Podman**: system-level (root) quadlet support, socket/units in place, storage
   configured on the SD card sensibly.
7. **Unprivileged port 80**: `net.ipv4.ip_unprivileged_port_start=80` as a sysctl drop-in,
   so the arbiter's status page binds :80 from a user unit without capabilities games.
8. **udev and groups**: the user in the groups needed for the SDR, the sound card and the
   camera; udev rules for stable SDR access.
9. **Verification step**: a final read-only pass that reports what is present (SDR via
   `rtl_test`, sound cards, camera, disk space, time sync) without changing anything, and
   exits non-zero if something *required* is missing.

### Makefile

`src/pi/Makefile` with `provision`, `deploy`, `logs`, `status`, `shell`, `check`, `help`,
and the standard `all`/`clean`/`distclean`. `deploy` rsyncs `src/pi/` and `src/shared/` to
the host and restarts the units; there is **no git on the Pi**, the repo is the source of
truth and the Pi is a target.

## Decided already, do not redesign

- Own Python tool, **no Ansible** (one dependency-free file beats a framework for nine
  steps on one host).
- **System quadlets for containers, user session for the arbiter and audio.** The box is
  protected and not internet-facing; device passthrough matters more than rootless purity.
- Hostname `borg-pi`, never a hardcoded IP.

## Exit criteria

- A fresh Pi reaches the target state with one command.
- Running it a second time changes nothing and says so, step by step.
- `--dry-run` on a fresh host prints a plausible full plan without touching it.
- The host's real Python version is recorded in `../README.md`.
- `make -C src/pi check` green (the step list and its probes are pure logic and are
  unit-tested without a host).

## Cannot be verified without hardware

`rtl_test` output, the presence of the USB sound card and the camera. Those probes must
*report* rather than fail the run: a Pi with no SDR attached is a valid state and M0 must
complete on it.

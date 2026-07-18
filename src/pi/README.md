# src/pi — borg-pi5 software

Orchestration/application logic for the borg-pi5, beyond the third-party services in
[`quadlets/`](quadlets/). **The build plan is in
[`implementation-plan.md`](implementation-plan.md)** (decided 2026-07-17: Python
provisioning tool, system quadlets + user-session arbiter, pydantic config, health
registry + status page, milestones M0–M4+). Code not started yet; M0 (provisioning) is
first.

## Provisioning model

**Manual, one-time, out of scope for this directory:** flashing the Pi OS image,
configuring WiFi and enabling SSH. Done by hand on a fresh SD card; not scripted.

**Everything from that point on is scripted and tracked here.** Once the Pi answers over
SSH, every further step — packages installed, files copied (scp targets), quadlets/units
enabled, config placed — is driven by a script living in `src/pi/`, run from a control
machine (not typed by hand on the Pi itself). Two goals this buys:
- **Reproducibility:** rebuilding or upgrading the Pi's software state is re-running the
  script, not remembering a sequence of manual steps.
- **Fast recovery from SD failure:** reflash the base image + WiFi/SSH by hand (the one
  manual step), then re-run the script to reach the exact same state — no rebuilding the
  setup from memory.

Not yet built (`src/pi/` has no code yet) — recorded here as the target shape for when
provisioning work starts. Per the project's Python conventions (`../CLAUDE.md`), the
script itself should be Python, not a shell script, once it grows past trivial glue.

## Setup notes (before code)

- **Reliable time source — NTP only, no RTC battery.** The Pi has no clock across
  power-off and the unit boots cold, but correct timestamps are load-bearing (the U6 bird
  log, U5 events). Sync via NTP at boot and **keep retrying a pool of NTP servers** until
  it succeeds (`systemd-timesyncd`/chrony with a server pool). Until the first sync the
  clock is wrong, so **gate timestamped writes** (bird log, events) on sync status rather
  than persisting a wrong time. See the 2026-07-16 decision-log entry.

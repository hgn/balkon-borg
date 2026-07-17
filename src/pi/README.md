# src/pi — borg-pi5 software

Not started. Will hold whatever orchestration/application logic the borg-pi5 needs
beyond the third-party services in [`quadlets/`](quadlets/). See
[`../README.md`](../README.md) for the open architecture questions this depends on.

## Setup notes (before code)

- **Reliable time source.** The Pi has no clock across power-off and the unit boots cold,
  but correct timestamps are load-bearing (the U6 bird log, U5 events). Sync via NTP at
  boot and **keep retrying a pool of NTP servers** until it succeeds
  (`systemd-timesyncd`/chrony with a server pool); trust timestamps only once synced.
  Add a **coin cell to the Pi 5 RTC (J5)** to bridge the boot gap before NTP catches up.
  See the 2026-07-16 decision-log entry.

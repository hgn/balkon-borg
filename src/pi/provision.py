#!/usr/bin/env python3
"""Provision borg-pi5 from a fresh Pi OS Lite image to a host ready for the arbiter.

Runs on the control machine, not on the Pi: standard library only, driving OpenSSH and
rsync, so it works on a bare machine with no virtualenv. That matters, because the day
this is needed most is the day the SD card died.

Every step has a probe and an action. The probe answers "is this already true?", the
action only runs when it is not, so a second run is a no-op and says so. See
`setup.md` for the technology and `tasks/m0-provisioning.md` for the package.
"""

from __future__ import annotations

import argparse
import hashlib
import shlex
import subprocess
import sys
import tempfile
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

DEFAULT_HOST = "borg-pi"
DEFAULT_USER = "pfeifer"
MIN_PYTHON = (3, 12)

HERE = Path(__file__).resolve().parent
CONFIG = HERE / "config"
QUADLETS = HERE / "quadlets"
SHARED = HERE.parent / "shared"

# Everything the Pi needs from the distribution. Deliberately unpinned: this box
# tracks Raspberry Pi OS, and pinning would only mean fighting apt later.
PACKAGES = [
    "podman",
    "rsync",
    "python3-venv",
    "python3-pip",
    "pipewire",
    "pipewire-audio",
    "wireplumber",
    "rtl-sdr",
    "nfs-common",
]

# Groups the arbiter's user needs for the hardware it touches.
GROUPS = ["audio", "video", "plugdev", "dialout"]

STORAGE_DIRS = [
    "/srv/borg",
    "/srv/borg/mosquitto/config",
    "/srv/borg/mosquitto/data",
    "/srv/borg/media",
    "/srv/borg/media/timelapse",
    "/srv/borg/birdnet",
    "/srv/borg/clips",
    "/srv/borg/apk",
    "/srv/borg/app",
]


@dataclass(frozen=True)
class Result:
    code: int
    out: str = ""
    err: str = ""

    @property
    def ok(self) -> bool:
        return self.code == 0


class Runner:
    """Executes a command locally. The seam tests replace."""

    def run(self, argv: Sequence[str], stdin: bytes | None = None) -> Result:
        p = subprocess.run(argv, input=stdin, capture_output=True)
        return Result(p.returncode, p.stdout.decode(errors="replace"),
                      p.stderr.decode(errors="replace"))


class Host:
    """A Pi reachable over SSH, with one multiplexed connection for the whole run.

    Mutating operations go through [sudo] and [put]; in dry-run mode they are printed
    instead of executed, while probes still run so the plan reflects the real host. If
    the host cannot be reached at all, dry-run keeps going and reports every step as
    pending, which is what you want when planning against hardware that is not there
    yet.
    """

    def __init__(self, host: str, user: str, *, runner: Runner | None = None,
                 dry_run: bool = False, control_path: str | None = None) -> None:
        self.host = host
        self.user = user
        self.runner = runner or Runner()
        self.dry_run = dry_run
        self.offline = False
        self._control = control_path
        self.planned: list[str] = []

    @property
    def target(self) -> str:
        return f"{self.user}@{self.host}"

    def _ssh_argv(self, command: str) -> list[str]:
        argv = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
        if self._control:
            argv += ["-o", "ControlMaster=auto", "-o", f"ControlPath={self._control}",
                     "-o", "ControlPersist=60s"]
        return argv + [self.target, command]

    def sh(self, command: str, stdin: bytes | None = None) -> Result:
        """Runs a command on the Pi. Used for probes, so it never mutates."""
        if self.offline:
            return Result(255, err="host offline (dry run)")
        return self.runner.run(self._ssh_argv(command), stdin)

    def probe(self, command: str) -> bool:
        return self.sh(command).ok

    def user_run(self, command: str) -> Result:
        """Runs a *mutating* command as the login user (user units live there).

        Separate from [sh] on purpose: sh is for probes and must stay read-only, so a
        dry run can call it freely. Anything that changes the host goes through here
        or [sudo] and is recorded rather than executed while planning.
        """
        if self.dry_run:
            self.planned.append(command)
            return Result(0)
        return self.sh(command)

    def sudo(self, command: str, stdin: bytes | None = None) -> Result:
        """Runs a command as root. Recorded rather than executed in dry-run mode."""
        if self.dry_run:
            self.planned.append(command)
            return Result(0)
        return self.sh(f"sudo -n sh -c {shlex.quote(command)}", stdin)

    def put(self, local: Path, remote: str, *, mode: str = "0644",
            owner: str = "root:root") -> Result:
        """Writes a local file to a root-owned path on the Pi."""
        if self.dry_run:
            self.planned.append(f"install {local.name} -> {remote}")
            return Result(0)
        data = local.read_bytes()
        parent = str(Path(remote).parent)
        cmd = (f"mkdir -p {shlex.quote(parent)} && cat > {shlex.quote(remote)} && "
               f"chmod {mode} {shlex.quote(remote)} && chown {owner} {shlex.quote(remote)}")
        return self.sh(f"sudo -n sh -c {shlex.quote(cmd)}", data)

    def file_matches(self, local: Path, remote: str) -> bool:
        """True when the Pi already holds exactly this file."""
        want = hashlib.sha256(local.read_bytes()).hexdigest()
        got = self.sh(f"sha256sum {shlex.quote(remote)} 2>/dev/null | cut -d' ' -f1")
        return got.ok and got.out.strip() == want


@dataclass(frozen=True)
class Step:
    name: str
    summary: str
    probe: Callable[[Host], bool]
    apply: Callable[[Host], None]


class StepFailed(Exception):
    """An action could not complete. Carries what to look at, not a stack trace."""


def _check(result: Result, what: str) -> None:
    if not result.ok:
        detail = (result.err or result.out).strip().splitlines()
        tail = detail[-1] if detail else f"exit {result.code}"
        raise StepFailed(f"{what}: {tail}")


def file_step(name: str, summary: str, local: Path, remote: str, *,
              mode: str = "0644", after: str | None = None) -> Step:
    """A config file that must exist on the Pi with exactly this content."""

    def apply(host: Host) -> None:
        _check(host.put(local, remote, mode=mode), f"writing {remote}")
        if after is not None:
            _check(host.sudo(after), f"after writing {remote}: {after}")

    return Step(name, summary, lambda h: h.file_matches(local, remote), apply)


# --- the steps ------------------------------------------------------------------


def step_preflight() -> Step:
    """Fails early and clearly rather than letting later steps fail obscurely."""

    def probe(host: Host) -> bool:
        return False  # always report; it is cheap and it is the first thing you read

    def apply(host: Host) -> None:
        if host.offline:
            # Planning against hardware that does not exist yet: there is nothing to
            # check, and refusing here would hide the rest of the plan.
            print("  (host offline, checks skipped)")
            return

        reach = host.sh("echo ok")
        if not reach.ok:
            raise StepFailed(
                f"cannot reach {host.target} over SSH. Is the Pi up and does "
                f"`ssh {host.target}` work with key auth? ({reach.err.strip()})")

        whoami = host.sh("id -un").out.strip()
        if whoami != host.user:
            raise StepFailed(f"expected user {host.user}, got {whoami}")

        arch = host.sh("uname -m").out.strip()
        if arch != "aarch64":
            raise StepFailed(f"expected a 64-bit image (aarch64), got {arch}")

        if not host.sh("sudo -n true").ok:
            raise StepFailed("passwordless sudo does not work; provisioning needs it")

        version = host.sh("python3 -c 'import sys; print(\"%d.%d\" % sys.version_info[:2])'")
        _check(version, "reading the Python version")
        got = tuple(int(p) for p in version.out.strip().split("."))
        if got < MIN_PYTHON:
            raise StepFailed(
                f"Python {got[0]}.{got[1]} is older than the required "
                f"{MIN_PYTHON[0]}.{MIN_PYTHON[1]}; reflash with a current image")

        print(f"  {host.target}: {arch}, Python {'.'.join(str(p) for p in got)}, sudo ok")

    return Step("preflight", "reachable, right user, 64-bit, sudo, Python version",
                probe, apply)


def step_packages() -> Step:
    query = " ".join(shlex.quote(p) for p in PACKAGES)

    def probe(host: Host) -> bool:
        # dpkg-query exits non-zero as soon as one package is unknown, which is
        # exactly the "not all installed" answer we want.
        return host.probe(f"dpkg-query -W -f='${{Status}}\\n' {query} 2>/dev/null "
                          f"| grep -cv '^install ok installed$' | grep -q '^0$'")

    def apply(host: Host) -> None:
        _check(host.sudo("apt-get update"), "apt-get update")
        _check(host.sudo(f"DEBIAN_FRONTEND=noninteractive apt-get install -y {query}"),
               "installing packages")

    return Step("packages", f"{len(PACKAGES)} distribution packages", probe, apply)


def step_dirs() -> Step:
    dirs = " ".join(shlex.quote(d) for d in STORAGE_DIRS)

    def probe(host: Host) -> bool:
        tests = " && ".join(f"test -d {shlex.quote(d)}" for d in STORAGE_DIRS)
        return host.probe(tests)

    def apply(host: Host) -> None:
        _check(host.sudo(f"mkdir -p {dirs}"), "creating the storage layout")
        _check(host.sudo(f"chown -R {host.user}:{host.user} /srv/borg"),
               "taking ownership of /srv/borg")

    return Step("dirs", "storage layout under /srv/borg", probe, apply)


def step_linger() -> Step:
    def probe(host: Host) -> bool:
        r = host.sh(f"loginctl show-user {shlex.quote(host.user)} -p Linger --value")
        return r.ok and r.out.strip() == "yes"

    def apply(host: Host) -> None:
        _check(host.sudo(f"loginctl enable-linger {shlex.quote(host.user)}"),
               "enabling linger")

    return Step("linger", "user units run without a login", probe, apply)


def step_groups() -> Step:
    def probe(host: Host) -> bool:
        r = host.sh("id -nG")
        if not r.ok:
            return False
        have = set(r.out.split())
        return all(g in have for g in GROUPS)

    def apply(host: Host) -> None:
        _check(host.sudo(f"usermod -aG {','.join(GROUPS)} {shlex.quote(host.user)}"),
               "adding hardware groups")
        print("  note: group membership applies on the next login")

    return Step("groups", f"user in {', '.join(GROUPS)}", probe, apply)


def step_quadlet_dir() -> Step:
    path = "/etc/containers/systemd"
    return Step(
        "quadlet-dir", "systemd picks up Podman quadlets",
        lambda h: h.probe(f"test -d {path}"),
        lambda h: _check(h.sudo(f"mkdir -p {path}"), f"creating {path}"),
    )


# The accounts the broker ACL distinguishes. They share one password: the separation
# exists so the broker can enforce who may write what, not to keep secrets from each
# other (borg.yaml explains the reasoning).
BROKER_USERS = ["arbiter", "app", "esp"]


def read_broker_password(path: Path) -> str:
    """Pulls broker.password out of borg.yaml without a YAML library.

    provision.py is standard library only (it has to run on a bare control machine),
    and this is the one value it needs from the config, which is what keeps a
    fifteen-line parser reasonable instead of embarrassing.
    """
    in_broker = False
    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0:
            in_broker = stripped == "broker:"
            continue
        if in_broker and indent == 2 and stripped.startswith("password:"):
            password = stripped.partition(":")[2].strip().strip("\"'")
            if not password:
                raise StepFailed(f"{path}: broker.password is empty")
            return password
    raise StepFailed(f"{path}: found no broker.password")


def step_mosquitto_passwd() -> Step:
    """Builds the broker's password file from borg.yaml.

    Hashing happens inside the Mosquitto image itself, so the Pi needs no mosquitto
    tools of its own. The probe can only compare the user list: the hashes are salted
    and differ on every run, so a *changed password* is invisible to it. Changing the
    password therefore means `--only mosquitto-passwd`, which setup.md says out loud.
    """
    remote = "/srv/borg/mosquitto/config/passwd"

    def probe(host: Host) -> bool:
        read_broker_password(SHARED / "borg.yaml")  # fail here if the config is broken
        got = host.sh(f"cut -d: -f1 {shlex.quote(remote)} 2>/dev/null | sort")
        return got.ok and got.out.split() == sorted(BROKER_USERS)

    def apply(host: Host) -> None:
        password = read_broker_password(SHARED / "borg.yaml")
        _check(host.sudo(f"rm -f {shlex.quote(remote)}"), "clearing the password file")
        for i, user in enumerate(sorted(BROKER_USERS)):
            create = "-c " if i == 0 else ""
            cmd = (f"podman run --rm -v /srv/borg/mosquitto/config:/mosquitto/config:Z "
                   f"docker.io/library/eclipse-mosquitto:2 "
                   f"mosquitto_passwd -b {create}/mosquitto/config/passwd "
                   f"{shlex.quote(user)} {shlex.quote(password)}")
            _check(host.sudo(cmd), f"adding broker user {user}")
        _check(host.sudo(f"chmod 0700 {shlex.quote(remote)}"), "protecting the password file")

    return Step("mosquitto-passwd", "broker users, one shared password", probe, apply)


def step_arbiter_unit() -> Step:
    """Installs and enables the arbiter's user unit (the binary arrives via `make deploy`)."""
    local = CONFIG / "borg-arbiter.service"
    remote = f"~/.config/systemd/user/borg-arbiter.service"

    def probe(host: Host) -> bool:
        if not host.file_matches(local, remote.replace("~", f"/home/{host.user}")):
            return False
        r = host.sh("systemctl --user is-enabled borg-arbiter 2>/dev/null")
        return r.ok and r.out.strip() == "enabled"

    def apply(host: Host) -> None:
        path = f"/home/{host.user}/.config/systemd/user/borg-arbiter.service"
        _check(host.put(local, path, owner=f"{host.user}:{host.user}"),
               "installing the arbiter unit")
        _check(host.user_run("systemctl --user daemon-reload && "
                             "systemctl --user enable borg-arbiter"),
               "enabling the arbiter unit")

    return Step("arbiter-unit", "arbiter starts at boot (needs `make deploy` for the binary)",
                probe, apply)


def build_steps() -> list[Step]:
    """The plan, in order. Each entry is independent of the ones after it."""
    return [
        step_preflight(),
        step_packages(),
        file_step("timesync", "NTP pool + retry until synced",
                  CONFIG / "timesyncd.conf", "/etc/systemd/timesyncd.conf",
                  after="systemctl restart systemd-timesyncd"),
        step_dirs(),
        file_step("media-tmpfs", "volatile media directory as tmpfs",
                  CONFIG / "srv-borg-media.mount",
                  "/etc/systemd/system/srv-borg-media.mount",
                  after="systemctl daemon-reload && systemctl enable --now srv-borg-media.mount"),
        step_linger(),
        step_quadlet_dir(),
        file_step("port80", "unprivileged binding of port 80",
                  CONFIG / "borg-ports.conf", "/etc/sysctl.d/90-borg-ports.conf",
                  after="sysctl --system"),
        file_step("sdr-blacklist", "keep the DVB driver off the SDR",
                  CONFIG / "borg-rtlsdr-blacklist.conf",
                  "/etc/modprobe.d/borg-rtlsdr-blacklist.conf",
                  after="modprobe -r dvb_usb_rtl28xxu 2>/dev/null || true"),
        file_step("sdr-udev", "SDR readable without root",
                  CONFIG / "borg-sdr.rules", "/etc/udev/rules.d/99-borg-sdr.rules",
                  after="udevadm control --reload-rules && udevadm trigger"),
        step_groups(),
        # M1: the broker and the arbiter's unit. The arbiter binary itself is not
        # provisioned, it is deployed (`make deploy`), because it changes far more
        # often than the system underneath it.
        file_step("mosquitto-conf", "broker configuration",
                  CONFIG / "mosquitto.conf", "/srv/borg/mosquitto/config/mosquitto.conf"),
        file_step("mosquitto-acl", "broker access rules",
                  CONFIG / "mosquitto-acl", "/srv/borg/mosquitto/config/acl"),
        step_mosquitto_passwd(),
        file_step("mosquitto-quadlet", "broker runs as a system container",
                  QUADLETS / "mosquitto.container",
                  "/etc/containers/systemd/mosquitto.container",
                  after="systemctl daemon-reload && systemctl start mosquitto"),
        step_arbiter_unit(),
    ]


# --- hardware report ------------------------------------------------------------

# Optional hardware: absent is a valid state (the stability principle, README.md), so
# these are reported and never fail the run.
PROBES = [
    ("clock", "timedatectl show -p NTPSynchronized --value", "yes"),
    ("sdr", "rtl_test -t 2>&1 | grep -q 'Found 1 device' && echo yes", "yes"),
    ("sound", "aplay -l 2>/dev/null | grep -q ^card && echo yes", "yes"),
    ("camera", "test -e /dev/video0 && echo yes", "yes"),
]


def report(host: Host) -> None:
    """Read-only pass: what is actually attached right now."""
    print("hardware:")
    for name, command, expect in PROBES:
        r = host.sh(command)
        state = "ok" if r.ok and r.out.strip() == expect else "missing"
        print(f"  {name:<8} {state}")
    free = host.sh("df -h /srv | tail -1 | awk '{print $4}'").out.strip()
    if free:
        print(f"  {'disk':<8} {free} free")


# --- driver ---------------------------------------------------------------------


def run_steps(steps: Sequence[Step], host: Host) -> int:
    changed = 0
    for step in steps:
        if step.probe(host):
            print(f"[ok]   {step.name}: {step.summary}")
            continue
        print(f"[do]   {step.name}: {step.summary}")
        try:
            step.apply(host)
        except StepFailed as e:
            sys.stdout.flush()  # keep the failure next to the step it belongs to
            print(f"[fail] {step.name}: {e}", file=sys.stderr)
            print(f"\nstopped at step '{step.name}'. Fix the cause and re-run; "
                  f"completed steps are skipped.", file=sys.stderr)
            return 1
        changed += 1
    verb = "would apply" if host.dry_run else "applied"
    print(f"\n{len(steps)} steps, {changed} {verb}, {len(steps) - changed} already in place")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="provision borg-pi5 (idempotent; re-running is a no-op)")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"default: {DEFAULT_HOST}")
    parser.add_argument("--user", default=DEFAULT_USER, help=f"default: {DEFAULT_USER}")
    parser.add_argument("--only", metavar="STEP", help="run a single step by name")
    parser.add_argument("--list", action="store_true", help="show the steps and exit")
    parser.add_argument("--dry-run", action="store_true",
                        help="probe the host but change nothing")
    parser.add_argument("--report", action="store_true",
                        help="read-only hardware report, no provisioning")
    args = parser.parse_args(argv)

    steps = build_steps()

    if args.list:
        for step in steps:
            print(f"{step.name:<14} {step.summary}")
        return 0

    if args.only is not None:
        steps = [s for s in steps if s.name == args.only]
        if not steps:
            print(f"no such step: {args.only} (try --list)", file=sys.stderr)
            return 2

    with tempfile.TemporaryDirectory(prefix="borg-ssh-") as tmp:
        host = Host(args.host, args.user, dry_run=args.dry_run,
                    control_path=f"{tmp}/control")
        if args.dry_run and not host.sh("echo ok").ok:
            print(f"note: {host.target} is not reachable, planning against an "
                  f"empty host\n", file=sys.stderr)
            host.offline = True

        if args.report:
            report(host)
            return 0

        code = run_steps(steps, host)
        if args.dry_run and host.planned:
            print("\nwould run:")
            for line in host.planned:
                print(f"  {line}")
        return code


if __name__ == "__main__":
    raise SystemExit(main())

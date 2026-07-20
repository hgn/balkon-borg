"""Tests for the provisioning tool, all against a fake runner: no host involved.

The property that matters most is idempotence, so it is tested directly: with every
probe satisfied, not a single mutating command may reach the host.
"""

from __future__ import annotations

import sys
from collections.abc import Sequence
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import provision  # noqa: E402
from provision import Host, Result, Step, StepFailed, build_steps, main, run_steps  # noqa: E402


class FakeRunner:
    """Answers commands from a rule list, recording everything it was asked to run.

    Rules are (substring, Result) and the first match wins; anything unmatched is a
    success with empty output, which keeps the tests to the interesting cases.
    """

    def __init__(self, rules: Sequence[tuple[str, Result]] = ()) -> None:
        self.rules = list(rules)
        self.commands: list[str] = []
        self.stdins: list[bytes | None] = []

    def run(self, argv: Sequence[str], stdin: bytes | None = None) -> Result:
        command = argv[-1]
        self.commands.append(command)
        self.stdins.append(stdin)
        for needle, result in self.rules:
            if needle in command:
                return result
        return Result(0)

    @property
    def mutations(self) -> list[str]:
        """Commands that could have changed the host."""
        return [c for c in self.commands if "sudo" in c]


def host_with(rules: Sequence[tuple[str, Result]] = (), **kwargs: object) -> Host:
    runner = FakeRunner(rules)
    host = Host("test-pi", "tester", runner=runner, **kwargs)  # type: ignore[arg-type]
    return host


# --- the plan -------------------------------------------------------------------


def test_plan_starts_with_preflight_and_has_unique_names() -> None:
    steps = build_steps()
    assert steps[0].name == "preflight"
    names = [s.name for s in steps]
    assert len(names) == len(set(names))


def test_every_step_ships_the_file_it_installs() -> None:
    """A file step whose local file is missing would fail on the Pi, not here."""
    for path in provision.CONFIG.iterdir():
        assert path.is_file()
    # The steps reference these by name; if one is renamed the probe would raise.
    host = host_with()
    for step in build_steps():
        step.probe(host)  # must not raise (a missing local file would)


# --- idempotence ----------------------------------------------------------------


def satisfied_step(name: str, calls: list[str]) -> Step:
    return Step(name, "already true", lambda h: True,
                lambda h: calls.append(name))


def test_a_satisfied_plan_changes_nothing() -> None:
    calls: list[str] = []
    host = host_with()
    steps = [satisfied_step(f"s{i}", calls) for i in range(3)]

    assert run_steps(steps, host) == 0
    assert calls == []
    assert isinstance(host.runner, FakeRunner)
    assert host.runner.mutations == []


def test_an_unsatisfied_step_applies_once() -> None:
    calls: list[str] = []
    step = Step("s", "not yet", lambda h: False, lambda h: calls.append("applied"))

    assert run_steps([step], host_with()) == 0
    assert calls == ["applied"]


def test_a_failing_step_stops_the_run() -> None:
    calls: list[str] = []

    def boom(host: Host) -> None:
        raise StepFailed("no")

    steps = [
        Step("first", "", lambda h: False, boom),
        Step("second", "", lambda h: False, lambda h: calls.append("second")),
    ]
    assert run_steps(steps, host_with()) == 1
    assert calls == []  # nothing after the failure ran


# --- file steps -----------------------------------------------------------------


def test_file_step_is_satisfied_when_the_hash_matches(tmp_path: Path) -> None:
    local = tmp_path / "thing.conf"
    local.write_text("hello\n")
    digest = "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"

    host = host_with([("sha256sum", Result(0, f"{digest}\n"))])
    step = provision.file_step("f", "", local, "/etc/thing.conf")
    assert step.probe(host) is True


def test_file_step_writes_and_runs_its_follow_up(tmp_path: Path) -> None:
    local = tmp_path / "thing.conf"
    local.write_text("hello\n")

    host = host_with([("sha256sum", Result(0, "different\n"))])
    step = provision.file_step("f", "", local, "/etc/thing.conf",
                               after="systemctl daemon-reload")
    assert step.probe(host) is False
    step.apply(host)

    assert isinstance(host.runner, FakeRunner)
    assert b"hello\n" in [s for s in host.runner.stdins if s is not None]
    assert any("daemon-reload" in c for c in host.runner.mutations)


def test_a_failed_write_names_the_file(tmp_path: Path) -> None:
    local = tmp_path / "thing.conf"
    local.write_text("x")
    host = host_with([("cat >", Result(1, err="Permission denied"))])
    step = provision.file_step("f", "", local, "/etc/thing.conf")

    with pytest.raises(StepFailed, match="/etc/thing.conf"):
        step.apply(host)


# --- preflight ------------------------------------------------------------------


def test_preflight_rejects_an_old_python() -> None:
    host = host_with([
        ("id -un", Result(0, "tester\n")),
        ("uname -m", Result(0, "aarch64\n")),
        ("sys.version_info", Result(0, "3.9\n")),
    ])
    with pytest.raises(StepFailed, match="older than"):
        provision.step_preflight().apply(host)


def test_preflight_rejects_a_32_bit_image() -> None:
    host = host_with([
        ("id -un", Result(0, "tester\n")),
        ("uname -m", Result(0, "armv7l\n")),
    ])
    with pytest.raises(StepFailed, match="64-bit"):
        provision.step_preflight().apply(host)


def test_preflight_explains_an_unreachable_host() -> None:
    host = host_with([("echo ok", Result(255, err="Connection refused"))])
    with pytest.raises(StepFailed, match="cannot reach"):
        provision.step_preflight().apply(host)


def test_preflight_requires_passwordless_sudo() -> None:
    host = host_with([
        ("id -un", Result(0, "tester\n")),
        ("uname -m", Result(0, "aarch64\n")),
        ("sudo -n true", Result(1)),
    ])
    with pytest.raises(StepFailed, match="sudo"):
        provision.step_preflight().apply(host)


# --- probes that read the host --------------------------------------------------


def test_linger_probe_reads_loginctl() -> None:
    step = provision.step_linger()
    assert step.probe(host_with([("Linger", Result(0, "yes\n"))])) is True
    assert step.probe(host_with([("Linger", Result(0, "no\n"))])) is False


def test_groups_probe_needs_every_group() -> None:
    step = provision.step_groups()
    full = " ".join(provision.GROUPS)
    assert step.probe(host_with([("id -nG", Result(0, f"tester {full}\n"))])) is True
    assert step.probe(host_with([("id -nG", Result(0, "tester audio\n"))])) is False


# --- dry run --------------------------------------------------------------------


def test_dry_run_records_instead_of_executing(tmp_path: Path) -> None:
    local = tmp_path / "thing.conf"
    local.write_text("x")
    host = host_with([("sha256sum", Result(0, "nope\n"))], dry_run=True)

    provision.file_step("f", "", local, "/etc/thing.conf", after="systemctl restart x").apply(host)

    assert isinstance(host.runner, FakeRunner)
    assert host.runner.mutations == []
    assert any("thing.conf" in line for line in host.planned)
    assert any("systemctl restart x" in line for line in host.planned)


def test_an_offline_host_reports_every_step_as_pending() -> None:
    host = host_with(dry_run=True)
    host.offline = True
    assert host.probe("anything") is False


def test_dry_run_against_a_host_that_does_not_exist_yet_still_plans(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """The Pi may not be built yet; the plan is still the interesting output."""
    host = host_with(dry_run=True)
    host.offline = True

    assert run_steps(build_steps(), host) == 0

    out = capsys.readouterr().out
    for step in build_steps():
        assert step.name in out
    assert "would apply" in out
    assert isinstance(host.runner, FakeRunner)
    assert host.runner.mutations == []


# --- the command line -----------------------------------------------------------


def test_list_prints_the_plan_without_touching_anything(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--list"]) == 0
    out = capsys.readouterr().out
    assert "preflight" in out
    assert "packages" in out


def test_only_rejects_an_unknown_step(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--only", "nonsense", "--dry-run"]) == 2
    assert "no such step" in capsys.readouterr().err

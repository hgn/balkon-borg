#!/usr/bin/env python3
"""Automated pre-order verification for the carrier board.

Runs headless, no KiCad GUI, no user interaction, and returns a non-zero exit
code if any stage fails. Five stages:

  1  SKiDL ERC          - regenerate the netlist from code, electrical rule check
  2  KiCad DRC          - kicad-cli geometry/clearance/width/silk checks
  3  netlist <-> board  - board has not drifted from the code (connectivity)
  4  board-spec intent  - connector pinouts + series resistors match the spec
  5  fab outputs        - export gerbers/drill, sanity-check the 2-layer set,
                          render a top PNG (best effort)

Run it with the system python3 (stages 3-5 need pcbnew / kicad-cli):

    python3 verify.py        # or: make verify
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
PCB = HERE / "balkon-borg-carrier.kicad_pcb"
OUT = HERE / "output"
VENV_PY = HERE.parent / ".venv" / "bin" / "python"
KENV = {
    "KICAD9_SYMBOL_DIR": "/usr/share/kicad/symbols",
    "KICAD9_FOOTPRINT_DIR": "/usr/share/kicad/footprints",
}


def banner(n: int, title: str) -> None:
    print(f"\n=== stage {n}: {title} ===", file=sys.stderr)


def run(cmd: list[str], env: dict | None = None) -> int:
    print(f"$ {' '.join(cmd)}", file=sys.stderr)
    full = {**os.environ, **(env or {})}
    return subprocess.run(cmd, env=full).returncode


def stage1_erc() -> bool:
    banner(1, "SKiDL ERC + netlist regen")
    return run([str(VENV_PY), str(HERE / "gen-netlist.py"), "--strict"], KENV) == 0


def stage2_drc() -> bool:
    banner(2, "KiCad DRC")
    OUT.mkdir(exist_ok=True)
    rc = run(["kicad-cli", "pcb", "drc", "--exit-code-violations",
              "--format", "json", "-o", str(OUT / "drc.json"), str(PCB)])
    if rc == 0:
        return True
    print("stage 2 FAIL: DRC reported violations (see output/drc.json)",
          file=sys.stderr)
    return False


def stage3_consistency() -> bool:
    banner(3, "netlist <-> board")
    return run([sys.executable, str(HERE / "check-netlist-board.py")]) == 0


def stage4_intent() -> bool:
    banner(4, "board-spec intent")
    return run([sys.executable, str(HERE / "check-board-spec.py")]) == 0


def stage5_outputs() -> bool:
    banner(5, "fab outputs")
    gerbers = OUT / "gerbers"
    gerbers.mkdir(parents=True, exist_ok=True)
    if run(["kicad-cli", "pcb", "export", "gerbers", "-o", str(gerbers),
            str(PCB)]) != 0:
        print("stage 5 FAIL: gerber export failed", file=sys.stderr)
        return False
    if run(["kicad-cli", "pcb", "export", "drill", "-o", str(gerbers),
            str(PCB)]) != 0:
        print("stage 5 FAIL: drill export failed", file=sys.stderr)
        return False
    names = " ".join(p.name for p in gerbers.iterdir())
    required = ["F_Cu", "B_Cu", "Edge_Cuts"]
    missing = [layer for layer in required if layer not in names]
    if missing:
        print(f"stage 5 FAIL: expected 2-layer fab set, missing {missing}",
              file=sys.stderr)
        return False
    # Visual render is best effort: a headless box may lack a GL backend.
    if run(["kicad-cli", "pcb", "render", "--side", "top", "--background",
            "opaque", "-o", str(OUT / "board-top.png"), str(PCB)]) != 0:
        print("stage 5 note: PNG render unavailable here (gerbers are fine)",
              file=sys.stderr)
    print(f"stage 5 PASS: 2-layer gerber + drill set written to {gerbers}")
    return True


def main() -> int:
    if not PCB.is_file():
        print(f"error: no board at {PCB}", file=sys.stderr)
        return 1

    stages = [
        ("SKiDL ERC", stage1_erc),
        ("KiCad DRC", stage2_drc),
        ("netlist<->board", stage3_consistency),
        ("board-spec intent", stage4_intent),
        ("fab outputs", stage5_outputs),
    ]
    results: list[tuple[str, bool]] = []
    for name, fn in stages:
        try:
            results.append((name, fn()))
        except Exception as exc:                      # noqa: BLE001
            print(f"stage {name!r} crashed: {exc}", file=sys.stderr)
            results.append((name, False))

    print("\n=== verify summary ===", file=sys.stderr)
    for name, ok in results:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}", file=sys.stderr)
    failed = [n for n, ok in results if not ok]
    if failed:
        print(f"\nVERIFY FAILED: {', '.join(failed)}", file=sys.stderr)
        return 1
    print("\nVERIFY OK: board is consistent with the code and the spec")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

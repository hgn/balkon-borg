#!/usr/bin/env python3
"""Stage 3: netlist <-> board consistency.

Compares the freshly generated netlist against the committed .kicad_pcb and
fails if the board has drifted from the code. The check is by connectivity, not
by net name: two netlists agree when they partition the pads into the same
groups, regardless of what those nets are called (SKiDL auto-names some nets, so
a name compare would be fragile). Also checks that every schematic component is
on the board with the same value.

Needs the KiCad pcbnew python module, so run it with the system python3.

    python3 check-netlist-board.py [--net FILE] [--pcb FILE]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import netparse

HERE = Path(__file__).parent


def board_state(pcb_path: Path) -> tuple[dict[str, str], dict[str, set[tuple[str, str]]]]:
    """Read components (ref->value) and connected nets (name->pads) from a board."""
    import pcbnew

    board = pcbnew.LoadBoard(str(pcb_path))
    comps: dict[str, str] = {}
    nets: dict[str, set[tuple[str, str]]] = {}
    for fp in board.GetFootprints():
        ref = fp.GetReference()
        pads = list(fp.Pads())
        connected = [p for p in pads if p.GetNetname()]
        # Footprints with no connected pad are board-only decoration (mounting
        # holes, logos); keep them out of the electrical compare.
        if connected:
            comps[ref] = fp.GetValue()
        for pad in connected:
            nets.setdefault(pad.GetNetname(), set()).add((ref, pad.GetPadName()))
    return comps, nets


def partition(nets: dict[str, set[tuple[str, str]]]) -> set[frozenset[tuple[str, str]]]:
    return {frozenset(pads) for pads in nets.values() if pads}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--net", type=Path, default=HERE / "balkon-borg-carrier.net")
    ap.add_argument("--pcb", type=Path, default=HERE / "balkon-borg-carrier.kicad_pcb")
    args = ap.parse_args()

    for f in (args.net, args.pcb):
        if not f.is_file():
            print(f"stage 3 FAIL: missing {f}", file=sys.stderr)
            return 1

    net_comps, net_nets = netparse.parse(args.net)
    try:
        brd_comps, brd_nets = board_state(args.pcb)
    except ImportError:
        print("stage 3 FAIL: pcbnew not importable (use the system python3)",
              file=sys.stderr)
        return 1

    problems: list[str] = []

    # Components: same refs, same values.
    only_net = set(net_comps) - set(brd_comps)
    only_brd = set(brd_comps) - set(net_comps)
    if only_net:
        problems.append(f"components in netlist but not on board: {sorted(only_net)}")
    if only_brd:
        problems.append(f"connected components on board but not in netlist: "
                        f"{sorted(only_brd)}")
    for ref in sorted(set(net_comps) & set(brd_comps)):
        if net_comps[ref] != brd_comps[ref]:
            problems.append(f"value mismatch {ref}: netlist={net_comps[ref]!r} "
                            f"board={brd_comps[ref]!r}")

    # Connectivity: identical pad groupings.
    pn, pb = partition(net_nets), partition(brd_nets)
    for grp in sorted(pn - pb, key=lambda g: sorted(g)):
        problems.append(f"net group in netlist but not on board: {sorted(grp)}")
    for grp in sorted(pb - pn, key=lambda g: sorted(g)):
        problems.append(f"net group on board but not in netlist: {sorted(grp)}")

    if problems:
        print(f"stage 3 FAIL: netlist and board disagree ({len(problems)} issue(s)):",
              file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    print(f"stage 3 PASS: {len(net_comps)} components and "
          f"{len(pn)} net groups match between code and board")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

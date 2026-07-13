#!/usr/bin/env python3
"""Add a GND copper pour (both layers) with thermal reliefs, after routing.

Runs with the SYSTEM python (KiCad pcbnew), in three separate processes:

    /usr/bin/python3 add-ground-pour.py --pours       # 1
    /usr/bin/python3 add-ground-pour.py --rulearea    # 2
    /usr/bin/python3 add-ground-pour.py --fill        # 3

`make pour` chains them. They MUST be separate processes: pcbnew drops a rule
area on save if a pad zone-connection was set, or if a zone fill ran, in the same
session. So phase 1 writes the pours and the ESP GND pad overrides; phase 2 adds
the antenna rule area to the loaded board (no pad setter -> it survives); phase 3
fills (a loaded rule area survives the fill).

Thermal reliefs on the THT pads keep hand-soldering from wicking all the heat into
the plane; the ESP header GND pins bond straight to the plane through their routed
tracks instead. A no-copper-pour rule area sits under the ESP32-DevKit's antenna
end so the plane does not detune it. Idempotent.
"""

import sys
from pathlib import Path

import pcbnew

HERE = Path(__file__).parent
BOARD = HERE / "balkon-borg-carrier.kicad_pcb"

W, H = 150.0, 92.0        # board outline (must match place-board.py)
EDGE_INSET = 0.5          # pour pulled in from the board edge (mm)
# Antenna keep-out: the DevKit's PCB antenna sits at its top end, above the two
# header columns (placed at x=44/69, y=18). Keep the pour clear of that top strip
# so the plane does not detune it.
ANT_KEEPOUT = (40.0, 0.0, 74.0, 16.0)   # x0, y0, x1, y1 (mm)


def mm(v: float) -> int:
    return pcbnew.FromMM(v)


def poly(pts):
    chain = pcbnew.SHAPE_LINE_CHAIN()
    for x, y in pts:
        chain.Append(pcbnew.VECTOR2I(x, y))
    chain.SetClosed(True)
    return chain


def add_pours() -> None:
    """Phase 1: GND pours on both layers + solid-bond the ESP header GND pins."""
    b = pcbnew.LoadBoard(str(BOARD))
    gnd = b.FindNet("GND").GetNetCode()
    # Remove existing zones (pours and rule areas). Collect them first via the typed
    # GetArea API: objects fetched fresh are typed, but fetching inside the removal
    # loop yields untyped SwigPyObjects that b.Remove() chokes on / skips.
    areas = [b.GetArea(i) for i in range(b.GetAreaCount())]
    for z in areas:
        b.Remove(z)

    ins = mm(EDGE_INSET)
    rect = [(ins, ins), (mm(W) - ins, ins), (mm(W) - ins, mm(H) - ins), (ins, mm(H) - ins)]
    for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
        z = pcbnew.ZONE(b)
        z.SetLayer(layer)
        z.SetNetCode(gnd)
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
        z.SetLocalClearance(mm(0.3))
        z.SetThermalReliefGap(mm(0.4))
        z.SetThermalReliefSpokeWidth(mm(0.4))
        z.SetMinThickness(mm(0.25))
        z.AddPolygon(poly(rect))
        b.Add(z)

    # Every GND pad is already tied to the plane by a routed GND track (Freerouting
    # runs before the pour exists). In this dense THT layout the extra thermal spokes
    # only pinch the pour into small isolated islands (starved-thermal DRC errors), so
    # drop the zone connection on all GND pads except J_PWR. The plane still merges with
    # the GND tracks, and hand-soldering is easier without a heat-sinking plane on the
    # pad. J_PWR keeps a solid plane tie for the 5 V return current.
    for fp in b.GetFootprints():
        if fp.GetReference() == "J_PWR":
            continue
        for pad in fp.Pads():
            if pad.GetNetname() == "GND":
                pad.SetLocalZoneConnection(pcbnew.ZONE_CONNECTION_NONE)

    pcbnew.SaveBoard(str(BOARD), b)


def add_rulearea() -> None:
    """Phase 2: no-copper-pour rule area under the DevKit antenna (loaded board)."""
    b = pcbnew.LoadBoard(str(BOARD))
    ax0, ay0, ax1, ay1 = ANT_KEEPOUT
    ka = pcbnew.ZONE(b)
    ka.SetIsRuleArea(True)
    ka.SetDoNotAllowCopperPour(True)
    ka.SetDoNotAllowTracks(False)
    ka.SetDoNotAllowVias(False)
    ka.SetDoNotAllowPads(False)
    ka.SetDoNotAllowFootprints(False)
    ka.SetAssignedPriority(0)
    ls = pcbnew.LSET()
    ls.AddLayer(pcbnew.F_Cu)
    ls.AddLayer(pcbnew.B_Cu)
    ka.SetLayerSet(ls)
    ka.AddPolygon(poly([(mm(ax0), mm(ay0)), (mm(ax1), mm(ay0)),
                        (mm(ax1), mm(ay1)), (mm(ax0), mm(ay1))]))
    b.Add(ka)
    pcbnew.SaveBoard(str(BOARD), b)


def fill_zones() -> None:
    """Phase 3: fill the pours (the loaded rule area survives the fill)."""
    b = pcbnew.LoadBoard(str(BOARD))
    pcbnew.ZONE_FILLER(b).Fill(b.Zones())
    pcbnew.SaveBoard(str(BOARD), b)


def main() -> int:
    phases = {"--pours": add_pours, "--rulearea": add_rulearea, "--fill": fill_zones}
    for flag, worker in phases.items():
        if flag in sys.argv:
            worker()
            print(f"done {flag}")
            return 0
    print("run one phase per process (see 'make pour'):\n"
          "  add-ground-pour.py --pours | --rulearea | --fill", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

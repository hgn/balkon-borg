#!/usr/bin/env python3
"""Compact placement + outline + mounting holes + silkscreen for the carrier board.

Runs with the SYSTEM python (KiCad pcbnew module), board CLOSED in KiCad:

    /usr/bin/python3 place-board.py

Does everything headless: clears old routing, places the 33 footprints compactly,
draws the final 150x92 outline, adds 4 M2.5 mounting holes at the corners (pattern
must match the enclosure carrier bosses in cad/balkon_borg.py), adds the "HagiOne"
silkscreen, saves, and exports the Specctra DSN for the autorouter.

ESP header row spacing (ESP_ROW) = 25.4 mm (1 inch), the official DevKitC-V4 value;
a caliper check on the actual module is still wise since clones vary.
"""

from pathlib import Path

import pcbnew

HERE = Path(__file__).parent
BOARD = HERE / "balkon-borg-carrier.kicad_pcb"
DSN = HERE / "balkon-borg-carrier.dsn"
MH_LIB = "/usr/share/kicad/footprints/MountingHole.pretty"

W, H = 150.0, 92.0                 # board outline
HOLE = ((7, 7), (143, 7), (7, 85), (143, 85))   # M2.5 mounting holes -> pattern 136x78
ESP_ROW = 25.4                     # ESP header row spacing: 25.4 mm (1 inch), the
                                   # official DevKitC-V4 value; caliper-check the real
                                   # module (clones vary) but this is confirmed.
MH_FP = "MountingHole_2.7mm_M2.5"  # M2.5 to match the enclosure carrier inserts (H3)


def mm(v: float) -> int:
    return pcbnew.FromMM(v)


def main() -> int:
    b = pcbnew.LoadBoard(str(BOARD))

    # Clear previous routing, outline, holes and silk (idempotent re-runs).
    # Collect all lists BEFORE removing anything (Remove() can invalidate the
    # container iterators in this pcbnew binding).
    old_tracks = list(b.GetTracks())
    old_drawings = list(b.GetDrawings())
    old_fps = list(b.GetFootprints())
    for tr in old_tracks:
        b.Remove(tr)
    for d in old_drawings:
        if d.GetLayer() == pcbnew.Edge_Cuts:
            b.Remove(d)
        elif isinstance(d, pcbnew.PCB_TEXT) and d.GetText() == "HagiOne":
            b.Remove(d)
    for fp in old_fps:
        if fp.GetReference() in ("H1", "H2", "H3", "H4"):
            b.Remove(fp)

    def place(ref: str, x: float, y: float, rot: float = 0.0) -> None:
        fp = b.FindFootprintByReference(ref)
        if fp is None:
            print(f"  ! {ref} not found")
            return
        fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
        fp.SetOrientationDegrees(rot)

    # Connector placement follows docs/wiring.md so cables reach their targets with
    # the shortest run: button/encoder connectors on the right edge (toward the +X end
    # wall), radar/BME/power on the down edge (toward the floor tower/BME/gland).

    # ESP32-DevKitC-V4 (official, 25.4 mm row spacing): two vertical 1x19 headers, left
    # of centre so the right edge is free for the button/encoder connectors.
    place("J2", 44, 18)
    place("J3", 44 + ESP_ROW, 18)

    # Down edge (enclosure floor side): 5 V in behind F1, then radar + BME whose cables
    # drop straight to the tower and the floor opening.
    place("J_PWR", 16, 8)
    place("F1", 30, 8)
    place("J_RADAR", 88, 8)
    place("J_BME", 108, 8)

    # 3V3 decoupling by the ESP 3V3 pin (top of J2).
    place("C1", 76, 18)
    place("C2", 76, 27)

    # Right short edge (toward the +X end wall): encoder + 4 buttons stacked; each
    # button's NPN driver just inboard of its connector.
    place("J_ENC", 132, 18, 90)
    for i, y in enumerate((32, 46, 60, 74)):
        place(f"J_BTN{i + 1}", 132, y, 90)
        place(f"Q{i + 1}", 118, y)

    # Series/driver resistors (15): three tidy rows in the free band below the ESP.
    # Values are assigned by the netlist; positions only avoid overlap, Freerouting
    # makes the connections.
    rows_y = (70, 80, 88)
    cols_x = (48, 62, 76, 90, 104)
    slots = [(x, y) for y in rows_y for x in cols_x]
    for i, (x, y) in enumerate(slots):
        place(f"R{i + 1}", x, y)

    # Board outline (closed rectangle) on Edge.Cuts.
    rect = pcbnew.PCB_SHAPE(b)
    rect.SetShape(pcbnew.SHAPE_T_RECT)
    rect.SetStart(pcbnew.VECTOR2I(mm(0), mm(0)))
    rect.SetEnd(pcbnew.VECTOR2I(mm(W), mm(H)))
    rect.SetLayer(pcbnew.Edge_Cuts)
    rect.SetWidth(mm(0.15))
    b.Add(rect)

    # M2.5 mounting holes at the corners; pattern mirrors the enclosure carrier inserts.
    for i, (x, y) in enumerate(HOLE):
        fp = pcbnew.FootprintLoad(MH_LIB, MH_FP)
        fp.SetReference(f"H{i + 1}")
        fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
        b.Add(fp)

    # "HagiOne" silkscreen, in the clear strip left of the ESP.
    t = pcbnew.PCB_TEXT(b)
    t.SetText("HagiOne")
    t.SetLayer(pcbnew.F_SilkS)
    t.SetPosition(pcbnew.VECTOR2I(mm(22), mm(46)))
    t.SetTextSize(pcbnew.VECTOR2I(mm(3), mm(3)))
    t.SetTextThickness(mm(0.5))
    b.Add(t)

    # Power netclass: wide (1.0 mm) traces for +5V/+5V_IN/GND so they carry the
    # current and F1 (2 A) actually protects them (a thin trace would fuse first).
    ns = b.GetDesignSettings().m_NetSettings
    nc = pcbnew.NETCLASS("Power")
    nc.SetTrackWidth(mm(1.0))
    ncmap = ns.GetNetclasses()
    ncmap["Power"] = nc
    ns.SetNetclasses(ncmap)
    for pat in ("+5V", "+5V_IN", "GND"):
        ns.SetNetclassPatternAssignment(pat, "Power")
    if hasattr(ns, "RecomputeEffectiveNetclasses"):
        ns.RecomputeEffectiveNetclasses()

    # DRC constraints to the fab (Aisler 2-layer) so DRC checks against real limits,
    # not KiCad defaults. Guarded so it survives pcbnew API changes.
    ds = b.GetDesignSettings()
    for attr, val in (("m_TrackMinWidth", 0.15), ("m_MinClearance", 0.15),
                      ("m_ViasMinSize", 0.45), ("m_MinThroughDrill", 0.30),
                      ("m_ViasMinAnnularWidth", 0.13), ("m_HoleToHoleMin", 0.25)):
        if hasattr(ds, attr):
            setattr(ds, attr, mm(val))

    pcbnew.SaveBoard(str(BOARD), b)
    pcbnew.ExportSpecctraDSN(b, str(DSN))
    print(f"placed {len(b.GetFootprints())} footprints (incl. 4 holes), wrote DSN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

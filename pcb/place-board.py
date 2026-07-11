#!/usr/bin/env python3
"""Compact placement + outline + mounting holes + silkscreen for the carrier board.

Runs with the SYSTEM python (KiCad pcbnew module), board CLOSED in KiCad:

    /usr/bin/python3 place-board.py

Does everything headless: clears old routing, places the 33 footprints compactly,
draws the final 150x92 outline, adds 4 M3 mounting holes at the corners (pattern
must match the enclosure carrier bosses in cad/balkon_borg.py), adds the "HagiOne"
silkscreen, saves, and exports the Specctra DSN for the autorouter.

The ESP header row spacing (ESP_ROW) is a placeholder; confirm against the real
DevKitC before the final board.
"""

from pathlib import Path

import pcbnew

HERE = Path(__file__).parent
BOARD = HERE / "balkon-borg-carrier.kicad_pcb"
DSN = HERE / "balkon-borg-carrier.dsn"
MH_LIB = "/usr/share/kicad/footprints/MountingHole.pretty"

W, H = 150.0, 92.0                 # board outline
HOLE = ((7, 7), (143, 7), (7, 85), (143, 85))   # M3 mounting holes -> pattern 136x78
ESP_ROW = 25.4                     # spacing between the two ESP header rows (VERIFY)


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

    # ESP32-DevKitC: two vertical 1x19 header columns, side by side.
    place("J2", 58, 21)
    place("J3", 58 + ESP_ROW, 21)

    # Top edge: power + sensors.
    place("J_PWR", 24, 9)
    place("F1", 42, 9)
    place("J_RADAR", 105, 9)
    place("J_BME", 128, 9)
    place("C1", 128, 22)
    place("C2", 128, 30)

    # Bottom edge: encoder + buttons, LED driver above each button.
    place("J_ENC", 24, 82)
    for i, x in enumerate((50, 74, 98, 122)):
        place(f"J_BTN{i + 1}", x, 82)
        place(f"Q{i + 1}", x, 73)

    # Resistors: two vertical columns flanking the ESP headers.
    for i in range(8):
        place(f"R{i + 1}", 40, 21 + i * 6)
    for i in range(8):
        place(f"R{i + 9}", 100, 21 + i * 6)

    # Board outline (closed rectangle) on Edge.Cuts.
    rect = pcbnew.PCB_SHAPE(b)
    rect.SetShape(pcbnew.SHAPE_T_RECT)
    rect.SetStart(pcbnew.VECTOR2I(mm(0), mm(0)))
    rect.SetEnd(pcbnew.VECTOR2I(mm(W), mm(H)))
    rect.SetLayer(pcbnew.Edge_Cuts)
    rect.SetWidth(mm(0.15))
    b.Add(rect)

    # M3 mounting holes at the corners (pattern mirrored into the enclosure).
    for i, (x, y) in enumerate(HOLE):
        fp = pcbnew.FootprintLoad(MH_LIB, "MountingHole_3.2mm_M3")
        fp.SetReference(f"H{i + 1}")
        fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
        b.Add(fp)

    # "HagiOne" silkscreen, top centre.
    t = pcbnew.PCB_TEXT(b)
    t.SetText("HagiOne")
    t.SetLayer(pcbnew.F_SilkS)
    t.SetPosition(pcbnew.VECTOR2I(mm(75), mm(15)))
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

    pcbnew.SaveBoard(str(BOARD), b)
    pcbnew.ExportSpecctraDSN(b, str(DSN))
    print(f"placed {len(b.GetFootprints())} footprints (incl. 4 holes), wrote DSN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

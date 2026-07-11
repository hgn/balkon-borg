#!/usr/bin/env python3
"""Apply a Freerouting Specctra session (.ses) back onto the board and save.

    /usr/bin/python3 apply-ses.py
"""

from pathlib import Path

import pcbnew

HERE = Path(__file__).parent
BOARD = HERE / "balkon-borg-carrier.kicad_pcb"
SES = HERE / "balkon-borg-carrier.ses"


def main() -> int:
    b = pcbnew.LoadBoard(str(BOARD))
    pcbnew.ImportSpecctraSES(b, str(SES))
    pcbnew.SaveBoard(str(BOARD), b)
    tracks = sum(1 for t in b.GetTracks() if t.GetClass() == "PCB_TRACK")
    vias = sum(1 for t in b.GetTracks() if t.GetClass() == "PCB_VIA")
    print(f"imported SES: {tracks} tracks, {vias} vias")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

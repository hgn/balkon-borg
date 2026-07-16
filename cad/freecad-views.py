#!/usr/bin/env python3
"""Extract clean 2D line-art views of the enclosure with FreeCAD (headless).

Run with FreeCAD's interpreter, not the venv:  ``freecadcmd freecad-views.py``.

Loads the built STEP, and for each named view rotates the solid into an upright
orientation, projects it along -Z with TechDraw's hidden-line removal, keeps only the
**visible** edges, discretises them to polylines, and writes them to ``build/views.json``.
``render-views.py`` (matplotlib, in the venv) then composes them into the overview PNG.
Split in two because FreeCAD's Python and the project venv cannot share a process.
"""

import json
import math
from pathlib import Path

import FreeCAD as App
import Part
import TechDraw

HERE = Path(__file__).resolve().parent
STEP = HERE / "build" / "balkon-borg-body.step"
OUT = HERE / "build" / "views.json"

DEFLECTION = 0.15   # curve tessellation (mm); small = smooth hex grilles / text


def R(axis, deg):
    return App.Rotation(App.Vector(*axis), deg)


# name -> rotation bringing the wanted view to face +Z (projected along -Z, up = +Y).
# The result's (x, y) is then the rotated solid's world (X, Y); render-views.py flips as
# needed. Chosen four: the terrace face, an end profile, the busy underside, and an iso.
VIEWS = [
    ("Rear (house)", R((1, 0, 0), -90)),
    ("Right end", R((0, 1, 0), -90)),
    ("Underside (terrace)", R((1, 0, 0), 180)),
    ("Isometric", R((0, 0, 1), 45).multiply(R((1, 0, 0), -54.736))),
]


def polylines(shape):
    lines = []
    for e in shape.Edges:
        try:
            pts = e.discretize(Deflection=DEFLECTION)
        except Exception:
            pts = e.Vertexes and [v.Point for v in e.Vertexes]
        if pts and len(pts) >= 2:
            lines.append([[round(p.x, 3), round(p.y, 3)] for p in pts])
    return lines


def main():
    shape = Part.Shape()
    shape.read(str(STEP))
    bb = shape.BoundBox
    out = {"dims": [round(bb.XLength), round(bb.YLength), round(bb.ZLength)], "views": []}

    for name, rot in VIEWS:
        s = shape.copy()
        s.Placement = App.Placement(App.Vector(0, 0, 0), rot)
        visible = TechDraw.project(s, App.Vector(0, 0, -1))[0]   # [0] = visible sharp edges
        lines = polylines(visible)
        xs = [p[0] for pl in lines for p in pl]
        ys = [p[1] for pl in lines for p in pl]
        out["views"].append({
            "name": name,
            "polylines": lines,
            "bbox": [min(xs), min(ys), max(xs), max(ys)],
        })
        print(f"{name}: {len(lines)} polylines")

    OUT.write_text(json.dumps(out))
    print(f"wrote {OUT}")


main()

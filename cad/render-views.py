#!/usr/bin/env python3
"""Compose the FreeCAD line-art views into one professional overview PNG.

Reads ``build/views.json`` (written by ``freecad-views.py`` under FreeCAD's interpreter)
and lays the four views out as a clean 2x2 engineering-drawing sheet with matplotlib.

Run: ``python render-views.py``  (or ``make views``, which runs the FreeCAD step first).
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from matplotlib.collections import LineCollection  # noqa: E402

HERE = Path(__file__).resolve().parent
VIEWS_JSON = HERE / "build" / "views.json"
OUT = HERE.parent / "docs" / "img" / "overview.png"

INK = "#1b1b1b"
FRAME = "#c8c8c8"

# per-view orientation fix-ups (in-plane rotation in degrees ccw, flip x, flip y), tuned
# to the TechDraw projection frame so each view reads upright.
TRANSFORMS = {
    "Rear (house)": (0.0, False, True),
    "Right end": (90.0, False, False),
    "Underside (terrace)": (0.0, False, False),
    "Isometric": (60.0, False, False),
}
ORDER = ["Rear (house)", "Right end", "Underside (terrace)", "Isometric"]


def orient(pl: np.ndarray, deg: float, flipx: bool, flipy: bool) -> np.ndarray:
    t = np.radians(deg)
    c, s = np.cos(t), np.sin(t)
    xy = pl @ np.array([[c, s], [-s, c]])
    if flipx:
        xy[:, 0] = -xy[:, 0]
    if flipy:
        xy[:, 1] = -xy[:, 1]
    return xy


def main() -> int:
    data = json.loads(VIEWS_JSON.read_text())
    w, d, h = data["dims"]
    views = {v["name"]: v for v in data["views"]}

    fig, axes = plt.subplots(2, 2, figsize=(12, 7.2))
    for ax, name in zip(axes.flat, ORDER):
        v = views[name]
        rot90, fx, fy = TRANSFORMS[name]
        segs = [orient(np.asarray(pl, float), rot90, fx, fy) for pl in v["polylines"]]
        ax.add_collection(LineCollection(segs, colors=INK, linewidths=0.5))
        allpts = np.concatenate(segs)
        lo, hi = allpts.min(0), allpts.max(0)
        ctr, span = (lo + hi) / 2, (hi - lo).max() * 0.52
        ax.set_xlim(ctr[0] - span, ctr[0] + span)
        ax.set_ylim(ctr[1] - span, ctr[1] + span)
        ax.set_aspect("equal")
        ax.set_xticks([])
        ax.set_yticks([])
        for s in ax.spines.values():
            s.set_edgecolor(FRAME)
        ax.set_title(name, fontsize=10, color=INK, pad=6)

    fig.suptitle(f"Balkon-Borg enclosure    {w} × {d} × {h} mm  (W × D × H)    SLS / PA12",
                 fontsize=12, color=INK, y=0.98)
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT, dpi=300, facecolor="white")
    plt.close(fig)
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

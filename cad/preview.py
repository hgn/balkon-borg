#!/usr/bin/env python3
"""Render a binary STL to an isometric PNG for a quick visual check.

Usage: python preview.py build/balkon-borg-body.stl [out.png]
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from mpl_toolkits.mplot3d.art3d import Poly3DCollection  # noqa: E402


def read_stl(path: Path) -> np.ndarray:
    data = path.read_bytes()
    n = struct.unpack_from("<I", data, 80)[0]
    tris = np.empty((n, 3, 3), dtype=np.float32)
    off = 84
    for i in range(n):
        vals = struct.unpack_from("<12f", data, off)
        tris[i] = np.array(vals[3:12]).reshape(3, 3)
        off += 50
    return tris


def main() -> int:
    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".png")
    tris = read_stl(src)

    elev = float(sys.argv[3]) if len(sys.argv) > 3 else 22.0
    azim = float(sys.argv[4]) if len(sys.argv) > 4 else -58.0
    er, ar = np.radians(elev), np.radians(azim)
    view = np.array([np.cos(er) * np.cos(ar), np.cos(er) * np.sin(ar), np.sin(er)])
    order = np.argsort(tris.mean(axis=1) @ view)   # painter's: far first
    tris = tris[order]

    fig = plt.figure(figsize=(9, 5))
    ax = fig.add_subplot(111, projection="3d")
    ax.add_collection3d(Poly3DCollection(
        tris, facecolor="#b9c4d0", edgecolor="#3a3f44", linewidths=0.2,
        alpha=1.0, sort_zpos=None))

    pts = tris.reshape(-1, 3)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    ctr, span = (lo + hi) / 2, (hi - lo).max() / 2
    for setlim, c in zip((ax.set_xlim, ax.set_ylim, ax.set_zlim), ctr):
        setlim(c - span, c + span)
    ax.set_box_aspect((1, 1, 1))
    ax.view_init(elev=elev, azim=azim)
    ax.set_xlabel("X (mm)"); ax.set_ylabel("Y (mm)"); ax.set_zlabel("Z up")
    fig.tight_layout()
    fig.savefig(out, dpi=140)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

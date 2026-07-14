#!/usr/bin/env python3
"""Render the enclosure from several viewpoints and montage them into one overview.

Reads the built STL (``build/balkon-borg-body.stl``), renders shaded views with a tiny
software renderer (backface cull + painter's sort + flat shading, no external renderer),
and fuses them into one image with ImageMagick ``montage``. Used for the README overview.

Run: ``python render-views.py``  (or ``make views``).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import trimesh  # noqa: E402
from matplotlib.collections import PolyCollection  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_STL = HERE / "build" / "balkon-borg-body.stl"
DEFAULT_OUT = HERE.parent / "docs" / "img" / "overview.png"

LIGHT = np.array([-0.35, -0.5, 0.78])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# name -> (viewing direction into the scene, up hint). Slightly angled so coplanar
# faces do not z-fight and the depth reads as a shape rather than a flat outline.
VIEWS: list[tuple[str, tuple[float, float, float], tuple[float, float, float]]] = [
    ("front (terrace)", (-0.12, -1.0, -0.10), (0, 0, 1)),
    ("rear (house)", (0.12, 1.0, -0.10), (0, 0, 1)),
    ("left end", (-1.0, 0.10, -0.12), (0, 0, 1)),
    ("right end", (1.0, 0.10, -0.12), (0, 0, 1)),
    ("top (ceiling)", (0.10, 0.14, 1.0), (0, 1, 0)),
    ("bottom (terrace)", (0.10, -0.14, -1.0), (0, 1, 0)),
    ("iso", (-0.62, 0.55, -0.52), (0, 0, 1)),
]


def render_view(verts: np.ndarray, faces: np.ndarray, normals: np.ndarray,
                direction: tuple[float, float, float], up_hint: tuple[float, float, float],
                half: float, out_path: Path) -> None:
    """Flat-shaded, backface-culled, painter-sorted orthographic render to a PNG."""
    d = np.asarray(direction, float)
    d /= np.linalg.norm(d)
    right = np.cross(np.asarray(up_hint, float), d)
    right /= np.linalg.norm(right)
    up = np.cross(d, right)

    front = (normals @ d) < -1e-6                       # faces pointing at the camera
    tris = verts[faces[front]]
    shade = np.clip(normals[front] @ LIGHT, 0.0, 1.0) * 0.5 + 0.42
    proj = np.stack([tris @ right, tris @ up], axis=-1)  # (k, 3, 2)
    order = np.argsort(tris.mean(1) @ d)[::-1]           # far first (painter's algorithm)

    rgb = np.column_stack([shade * 0.72, shade * 0.77, shade * 0.82, np.ones(shade.size)])
    fig, ax = plt.subplots(figsize=(4.2, 4.2))
    ax.add_collection(PolyCollection(proj[order], facecolors=rgb[order], edgecolors="none"))
    ax.set_xlim(-half, half)
    ax.set_ylim(-half, half)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.tight_layout(pad=0.05)
    fig.savefig(out_path, dpi=120, facecolor="white")
    plt.close(fig)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stl", type=Path, default=DEFAULT_STL, help="input STL")
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT, help="montage PNG")
    args = ap.parse_args()

    montage = shutil.which("montage")
    if montage is None:
        print("error: ImageMagick 'montage' not found on PATH", file=sys.stderr)
        return 1
    if not args.stl.exists():
        print(f"error: {args.stl} not found (run 'make' first)", file=sys.stderr)
        return 1

    mesh = trimesh.load(args.stl)
    mesh.apply_translation(-mesh.bounds.mean(axis=0))    # centre for a common scale
    half = float(np.abs(mesh.bounds).max()) * 1.05
    verts, faces, normals = mesh.vertices, mesh.faces, mesh.face_normals
    w, d, h = (mesh.bounds[1] - mesh.bounds[0])

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tiles: list[str] = []
        for name, direction, up_hint in VIEWS:
            png = Path(tmp) / f"{name.split()[0]}.png"
            render_view(verts, faces, normals, direction, up_hint, half, png)
            tiles += ["-label", name, str(png)]
            print(f"rendered {name}", file=sys.stderr)
        cmd = [montage, *tiles, "-tile", "4x2", "-geometry", "+6+6",
               "-background", "white", "-bordercolor", "#dddddd", "-border", "1",
               "-title", f"Balkon-Borg enclosure  {w:.0f} x {d:.0f} x {h:.0f} mm (W x D x H)",
               str(args.out)]
        subprocess.run(cmd, check=True)
    print(f"wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

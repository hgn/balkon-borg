#!/usr/bin/env python3
"""Annotate the board render with cable callouts to the external components.

SOURCE: pcb/board-top.png (the kicad-cli 3D render of balkon-borg-carrier.kicad_pcb)
as background, plus the connector positions from place-board.py (mm). Output:
board-annotated.png at 300 dpi. Re-run with `make -C pcb harness`.

The green PCB area is auto-detected to calibrate mm -> pixels (KiCad X->right,
Y->down, matching the top render).
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt      # noqa: E402
import numpy as np                   # noqa: E402
from PIL import Image                # noqa: E402

HERE = Path(__file__).parent
BOARD_W, BOARD_H = 150.0, 92.0       # must match place-board.py

# (ref, x_mm, y_mm, target label, side)
CONNECTORS = [
    ("J_PWR", 16, 8, "PSU / 5 V  (Wago)", "up"),
    ("J_RADAR", 88, 8, "LD2410B radar  (in the tower)", "up"),
    ("J_BME", 108, 8, "BME280  (bottom opening)", "up"),
    ("J_ENC", 132, 18, "EC11 rotary encoder", "right"),
    ("J_BTN1", 132, 32, "illuminated button 1", "right"),
    ("J_BTN2", 132, 46, "illuminated button 2", "right"),
    ("J_BTN3", 132, 60, "illuminated button 3", "right"),
    ("J_BTN4", 132, 74, "illuminated button 4", "right"),
]


def main() -> int:
    img = np.asarray(Image.open(HERE / "board-top.png").convert("RGB"))
    h, w = img.shape[:2]
    r, g, b = img[..., 0].astype(int), img[..., 1].astype(int), img[..., 2].astype(int)
    # PCB solder mask = dark and green-dominant (background is bright grey, shadow grey)
    green = (g - np.maximum(r, b) > 5) & (r + g + b < 350)
    ys, xs = np.where(green)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()

    def px(mx: float, my: float) -> tuple[float, float]:
        return x0 + mx / BOARD_W * (x1 - x0), y0 + my / BOARD_H * (y1 - y0)

    fig, ax = plt.subplots(figsize=(w / 100, h / 100), dpi=100)
    ax.imshow(img)
    ax.set_xlim(-0.42 * w, 1.30 * w)                    # room for the callouts
    ax.set_ylim(h, -0.06 * h)
    ax.axis("off")

    box = dict(boxstyle="round,pad=0.35", fc="#fffbe6", ec="#3a3f44", lw=1.2)
    arr = dict(arrowstyle="-", color="#c0392b", lw=1.6,
               connectionstyle="arc3,rad=0")
    up_x = np.linspace(x0 - 0.30 * w, x1 + 0.10 * w, sum(c[4] == "up" for c in CONNECTORS))
    ui = 0
    for ref, mx, my, target, side in CONNECTORS:
        cx, cy = px(mx, my)
        if side == "up":
            tx, ty = up_x[ui], -0.03 * h
            ha = "center"
            ui += 1
        else:
            tx, ty = x1 + 0.06 * w, cy
            ha = "left"
        ax.annotate(f"{ref}  →  {target}", xy=(cx, cy), xytext=(tx, ty),
                    fontsize=11, ha=ha, va="center", bbox=box, arrowprops=arr,
                    color="#222", zorder=5)
        ax.plot(cx, cy, "o", ms=7, mfc="#c0392b", mec="white", mew=1.2, zorder=6)

    out = HERE / "board-annotated.png"
    fig.savefig(out, dpi=300, bbox_inches="tight", facecolor="#e9eaf0")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

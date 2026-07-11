#!/usr/bin/env python3
"""Generate Aisler-ready fabrication outputs for the carrier board via kicad-cli.

Runs ERC and DRC, exports gerbers, drill files, a centroid/pos file and a BOM,
then zips the gerbers plus drill for upload. Diagnostics go to stderr, the path
of the final zip goes to stdout.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path


def run(cmd: list[str]) -> None:
    print(f"$ {' '.join(cmd)}", file=sys.stderr)
    subprocess.run(cmd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pcb", type=Path, help="path to the .kicad_pcb file")
    parser.add_argument(
        "-o", "--output", type=Path, default=Path("output"),
        help="output directory (default: ./output)",
    )
    args = parser.parse_args()

    pcb: Path = args.pcb
    if not pcb.is_file():
        print(f"error: no such PCB file: {pcb}", file=sys.stderr)
        return 1
    if shutil.which("kicad-cli") is None:
        print("error: kicad-cli not found on PATH", file=sys.stderr)
        return 1

    sch = pcb.with_suffix(".kicad_sch")
    out: Path = args.output
    gerber_dir = out / "gerbers"
    out.mkdir(parents=True, exist_ok=True)
    gerber_dir.mkdir(exist_ok=True)

    try:
        if sch.is_file():
            run(["kicad-cli", "sch", "erc", "--exit-code-violations",
                 "-o", str(out / "erc.rpt"), str(sch)])
            run(["kicad-cli", "sch", "export", "bom",
                 "-o", str(out / "bom.csv"), str(sch)])
        else:
            print(f"warning: no schematic at {sch}, skipping ERC and BOM",
                  file=sys.stderr)

        run(["kicad-cli", "pcb", "drc", "--exit-code-violations",
             "-o", str(out / "drc.rpt"), str(pcb)])
        run(["kicad-cli", "pcb", "export", "gerbers", "-o", str(gerber_dir),
             str(pcb)])
        run(["kicad-cli", "pcb", "export", "drill", "-o", str(gerber_dir),
             str(pcb)])
        run(["kicad-cli", "pcb", "export", "pos", "--format", "csv",
             "--units", "mm", "-o", str(out / "pos.csv"), str(pcb)])
    except subprocess.CalledProcessError as exc:
        print(f"error: kicad-cli failed (exit {exc.returncode})", file=sys.stderr)
        return exc.returncode

    zip_path = out / f"{pcb.stem}-aisler.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(gerber_dir.iterdir()):
            zf.write(f, f.name)
    print(zip_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

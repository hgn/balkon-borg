#!/usr/bin/env python3
"""Stage 4: board-spec <-> netlist intent check.

Reads the binding tables in docs/board-spec.md and checks that the generated
netlist really is what was specified. This catches the class of bug no DRC can:
a swapped connector pin or a wrong series-resistor value. Checked:

  * connector pinout   - each J_* pin carries the net the spec lists (power
                         names 5V/3V3/GND normalised; 5V accepts +5V or +5V_IN
                         because the fuse sits between J_PWR and the +5V rail)
  * series resistors   - each named signal net (RADAR_*, ENC_*, BTN*_SW) runs
                         through a resistor of the value the GPIO table states
  * I2C pull-ups       - SDA/SCL each see a 4k7 resistor
  * button LED drivers - four 1k base resistors, one per button

Not checked here: the GPIO-number-to-header-pin mapping, which needs the
external DevKitC-V4 pinout as ground truth. Stdlib + netparse only.

    python3 check-board-spec.py [--spec FILE] [--net FILE]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import netparse

HERE = Path(__file__).parent
SPEC = HERE / "docs" / "board-spec.md"


def parse_tables(spec_path: Path) -> tuple[list[dict], list[dict]]:
    """Return (gpio_rows, connector_rows) from the two markdown tables."""
    gpio: list[dict] = []
    conn: list[dict] = []
    table: str | None = None
    for line in spec_path.read_text().splitlines():
        s = line.strip()
        if not s.startswith("|"):
            table = None
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        low = [c.lower() for c in cells]
        if "series r" in low and "gpio" in low:
            table = "gpio"
            continue
        if "pinout" in low and "ref" in low:
            table = "conn"
            continue
        if set("".join(cells)) <= set("-: "):      # header separator row
            continue
        if table == "gpio" and len(cells) >= 5:
            gpio.append({"net": cells[0].strip("` "), "series_r": cells[4]})
        elif table == "conn" and len(cells) >= 3:
            conn.append({"ref": cells[0].strip("` "), "pins": cells[1],
                         "pinout": cells[2]})
    return gpio, conn


def norm_r(cell: str) -> str | None:
    """'220 Ohm' -> '220', '1 kOhm' -> '1k', '4.7 kOhm' -> '4k7', '-' -> None."""
    s = cell.replace("Ω", "").replace("Ohm", "").replace(" ", "").strip()
    if s in ("", "-", "–", "—"):
        return None
    m = re.fullmatch(r"(\d+)(?:\.(\d+))?k", s)
    if m:
        return f"{m.group(1)}k{m.group(2) or ''}"
    return s


def expected_nets(token: str) -> set[str]:
    u = token.upper()
    return {"5V": {"+5V", "+5V_IN"}, "GND": {"GND"}, "3V3": {"+3V3"}}.get(u, {token})


def clean_token(tok: str) -> str:
    return tok.split("(")[0].replace("`", "").strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--spec", type=Path, default=SPEC)
    ap.add_argument("--net", type=Path, default=HERE / "balkon-borg-carrier.net")
    args = ap.parse_args()
    for f in (args.spec, args.net):
        if not f.is_file():
            print(f"stage 4 FAIL: missing {f}", file=sys.stderr)
            return 1

    comps, nets = netparse.parse(args.net)
    pad2net = {pad: name for name, pads in nets.items() for pad in pads}
    gpio_rows, conn_rows = parse_tables(args.spec)
    problems: list[str] = []
    checks = 0

    # --- connector pinouts ------------------------------------------------
    for row in conn_rows:
        ref = row["ref"]
        tokens = [clean_token(t) for t in row["pinout"].split(",")]
        for i, tok in enumerate(tokens, start=1):
            checks += 1
            actual = pad2net.get((ref, str(i)))
            want = expected_nets(tok)
            if actual not in want:
                problems.append(f"{ref} pin {i}: spec wants {tok!r} "
                                f"({'/'.join(sorted(want))}), netlist has "
                                f"{actual!r}")

    # --- series resistor values ------------------------------------------
    def resistor_on(net: str) -> str | None:
        for ref, _pin in nets.get(net, ()):
            if ref.startswith("R"):
                return comps.get(ref)
        return None

    for row in gpio_rows:
        want_r = norm_r(row["series_r"])
        net = row["net"]
        if want_r is None or net not in nets:
            continue
        checks += 1
        got = resistor_on(net)
        if got != want_r:
            problems.append(f"net {net}: spec series R {want_r}, netlist has "
                            f"{got!r}")

    # --- I2C pull-ups -----------------------------------------------------
    for net in ("I2C_SDA", "I2C_SCL"):
        checks += 1
        vals = {comps.get(r) for r, _ in nets.get(net, ()) if r.startswith("R")}
        if "4k7" not in vals:
            problems.append(f"net {net}: expected a 4k7 pull-up, found {vals or 'none'}")

    # --- button LED base resistors ---------------------------------------
    checks += 1
    n_1k = sum(1 for v in comps.values() if v == "1k")
    if n_1k != 4:
        problems.append(f"expected four 1k NPN base resistors, netlist has {n_1k}")

    if problems:
        print(f"stage 4 FAIL: {len(problems)} spec mismatch(es) of {checks} checks:",
              file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    print(f"stage 4 PASS: {checks} checks against board-spec.md "
          f"({len(conn_rows)} connectors, {len(gpio_rows)} signal rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

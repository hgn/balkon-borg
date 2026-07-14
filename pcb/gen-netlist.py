#!/usr/bin/env python3
"""Generate the KiCad netlist for the Balkon-Borg sensor carrier via SKiDL.

The board (see docs/board-spec.md) is the ESP32 front plate: an ESP32-DevKitC-V4
socketed on two 1x19 headers, JST-XH connectors for radar, BME280, encoder and
four illuminated buttons, series resistors, NPN LED drivers and decoupling.

ESP pin positions follow the official ESP32-DevKitC-V4 header layout (J2 left,
J3 right, top to bottom). Run this, then import the .net into the KiCad PCB
editor and lay the board out.

    KICAD9_SYMBOL_DIR / KICAD9_FOOTPRINT_DIR must point at the KiCad libraries.
    python gen-netlist.py   ->   balkon-borg-carrier.net
"""

import argparse
import os
import sys
from pathlib import Path

os.environ.setdefault("KICAD9_SYMBOL_DIR", "/usr/share/kicad/symbols")
os.environ.setdefault("KICAD9_FOOTPRINT_DIR", "/usr/share/kicad/footprints")

from skidl import ERC, KICAD9, Net, Part, generate_netlist, set_default_tool  # noqa: E402
from skidl.logger import erc_logger  # noqa: E402

set_default_tool(KICAD9)

FP_HDR = "Connector_PinSocket_2.54mm:PinSocket_1x19_P2.54mm_Vertical"
FP_J2 = "Connector_JST:JST_XH_B2B-XH-A_1x02_P2.50mm_Vertical"
FP_J4 = "Connector_JST:JST_XH_B4B-XH-A_1x04_P2.50mm_Vertical"
FP_J5 = "Connector_JST:JST_XH_B5B-XH-A_1x05_P2.50mm_Vertical"
FP_R = "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal"
FP_CD = "Capacitor_THT:C_Disc_D5.0mm_W2.5mm_P5.00mm"
FP_CP = "Capacitor_THT:CP_Radial_D5.0mm_P2.50mm"
FP_Q = "Package_TO_SOT_THT:TO-92_Inline"
FP_PTC = "Capacitor_THT:C_Disc_D7.5mm_W5.0mm_P5.00mm"  # radial 2-lead PTC (5 mm pitch);
# VERIFY against the actual polyfuse part — a PTC is radial, not an axial resistor.


def res(val: str) -> Part:
    return Part("Device", "R", value=val, footprint=FP_R)


def conn(name: str, npins: int, fp: str, value: str) -> Part:
    return Part("Connector_Generic", f"Conn_01x{npins:02d}", ref=name,
                footprint=fp, value=value)


p5v, p3v3, gnd = Net("+5V"), Net("+3V3"), Net("GND")

# ESP32-DevKitC-V4, socketed on two 1x19 headers (J2 = left, J3 = right).
espL = Part("Connector_Generic", "Conn_01x19", ref="J2",
            footprint=FP_HDR, value="ESP32-DevKitC L")
espR = Part("Connector_Generic", "Conn_01x19", ref="J3",
            footprint=FP_HDR, value="ESP32-DevKitC R")
p5v += espL[19]          # J2.19 = 5V input to the DevKit
p3v3 += espL[1]          # J2.1  = 3V3 output from the DevKit regulator
gnd += espL[14], espR[1], espR[7]

# GPIO -> physical header pin (per DevKitC-V4 layout)
GPIO34, GPIO32, GPIO33, GPIO25 = espL[5], espL[7], espL[8], espL[9]
GPIO26, GPIO27, GPIO14, GPIO13 = espL[10], espL[11], espL[12], espL[15]
GPIO23, GPIO22, GPIO21 = espR[2], espR[3], espR[6]
GPIO19, GPIO18, GPIO17, GPIO16, GPIO4 = espR[8], espR[9], espR[11], espR[12], espR[13]


def series(outside, esp_pin, val: str, netname: str) -> None:
    """Outside connector pin -> series resistor -> ESP GPIO, named net outside."""
    r = res(val)
    Net(netname).connect(outside, r[1])
    r[2] += esp_pin


# 5 V input with resettable fuse.
jpwr = conn("J_PWR", 2, FP_J2, "5V in")
f1 = Part("Device", "Polyfuse", ref="F1", value="2A", footprint=FP_PTC)
Net("+5V_IN").connect(jpwr[1], f1[1])
f1[2] += p5v
gnd += jpwr[2]

# 3V3 decoupling.
c1 = Part("Device", "C", ref="C1", value="10uF", footprint=FP_CP)
c2 = Part("Device", "C", ref="C2", value="100nF", footprint=FP_CD)
for c in (c1, c2):
    p3v3 += c[1]
    gnd += c[2]

# Radar LD2410B (5V, GND, RX, TX) with 220R series. Presence comes over UART, so the
# separate OUT pin (GPIO34) is dropped (M10: it was dead copper) -> 4-pin connector.
jrad = conn("J_RADAR", 4, FP_J4, "LD2410B")
p5v += jrad[1]
gnd += jrad[2]
series(jrad[3], GPIO17, "220", "RADAR_RX")   # ESP TX2 -> radar RX
series(jrad[4], GPIO16, "220", "RADAR_TX")   # radar TX -> ESP RX2

# BME280 (3V3, GND, SCL, SDA), direct I2C + optional 4k7 pull-ups (DNP-capable).
jbme = conn("J_BME", 4, FP_J4, "BME280")
p3v3 += jbme[1]
gnd += jbme[2]
sda, scl = Net("I2C_SDA"), Net("I2C_SCL")
sda += jbme[4], GPIO21
scl += jbme[3], GPIO22
rsda, rscl = res("4k7"), res("4k7")
sda += rsda[1]
scl += rscl[1]
p3v3 += rsda[2], rscl[2]

# Rotary encoder EC11 (A, B, SW, GND) with 100R series.
jenc = conn("J_ENC", 4, FP_J4, "Encoder EC11")
series(jenc[1], GPIO32, "100", "ENC_A")
series(jenc[2], GPIO33, "100", "ENC_B")
series(jenc[3], GPIO25, "100", "ENC_SW")
gnd += jenc[4]

# Four illuminated buttons: SW via 100R; 5V LED switched low-side by an NPN.
btn_sw = [GPIO13, GPIO14, GPIO27, GPIO26]
btn_led = [GPIO4, GPIO23, GPIO18, GPIO19]
for i in range(4):
    jb = conn(f"J_BTN{i + 1}", 4, FP_J4, "Taster")
    series(jb[1], btn_sw[i], "100", f"BTN{i + 1}_SW")     # switch to GPIO
    gnd += jb[2]                                          # switch return
    p5v += jb[3]                                          # LED anode
    q = Part("Transistor_BJT", "BC337", ref=f"Q{i + 1}",
             footprint=FP_Q, value="BC337")
    Net(f"BTN{i + 1}_LEDK").connect(jb[4], q["C"])        # LED cathode -> collector
    rb = res("1k")
    q["B"] += rb[1]
    rb[2] += btn_led[i]                                  # base driven from GPIO
    gnd += q["E"]

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Generate the carrier netlist.")
    ap.add_argument("--strict", action="store_true",
                    help="run ERC and exit non-zero if it reports any error")
    args = ap.parse_args()

    ERC()
    errors = erc_logger.error.count + erc_logger.bare_error.count
    warnings = erc_logger.warning.count + erc_logger.bare_warning.count
    print(f"ERC: {errors} error(s), {warnings} warning(s) "
          "(unconnected ESP header pins are expected warnings)", file=sys.stderr)

    out = Path(__file__).parent / "balkon-borg-carrier.net"
    generate_netlist(file_=str(out))
    print(f"wrote {out}")

    if args.strict and errors:
        print(f"ERC failed with {errors} error(s)", file=sys.stderr)
        raise SystemExit(1)

#!/usr/bin/env python3
"""Parametric enclosure for the Balkon-Borg (CadQuery).

Ceiling-mounted under the balcony, LED panel facing FORWARD to the terrace.
Orientation in this model:

    X  = width (along the 43-pixel panel columns)
    Z  = up (toward the ceiling); +Z top wall, -Z bottom
    Y  = depth (front to back); +Y = front/terrace (OPEN light window),
         -Y = rear/house

Faces and their jobs:
    +Y front  : LED panel + diffuser in the open light window (light forward).
                Stays text-free.
    -Z bottom : buttons + encoder (reachable from below).
    -Y rear   : status/effect LEDs (small holes), cable gland, ventilation.
    +Z top    : ceiling side; lateral ears ("Nasen") with vertical screw holes,
                screwed up into the ceiling from below.
    +/-X ends : raised slogans.

The Pi 5 and the sensor carrier hang from the rear inner wall on bosses. Split at
X=0 into two halves for the print bed, aligned by 4 mm dowel pins in posts.

Dimensions are datasheet-derived with generous clearances (see PARAMETERS). The
LED panel size is an assumption (10 mm pitch) and drives the overall size.

Run: python balkon_borg.py   ->   writes STEP and STL into build/.

TODO: front rebate/seat for the panel + diffuser, camera opening + mount (mind the
short CSI cable to the rear-mounted Pi), radar membrane, ear gussets, bigger
slogans once placement is agreed on the new geometry.
"""

from __future__ import annotations

import math
from pathlib import Path

import cadquery as cq

# ---- PARAMETERS (mm) --------------------------------------------------------

# LED panel (ASSUMPTION: SK6812 8x43 at 10 mm pitch). Drives the front size.
PANEL_COLS = 43
PANEL_ROWS = 8
PANEL_PITCH = 10.0
PANEL_W = PANEL_COLS * PANEL_PITCH            # 430 (X)
PANEL_H = PANEL_ROWS * PANEL_PITCH            # 80  (Z)

BORDER = 15.0            # frame around the front light window
WALL = 3.0              # ASA wall thickness
DEPTH = 115.0           # internal depth front-to-back (Y); +20 mm gives the WLED
                        # controller ~25 mm clearance to the warm LED panel back

# Front seat: diffuser (opal acrylic) in a rebate, LED panel glued behind it.
WINDOW_W = PANEL_W + 4.0        # 434, light hole (all pixels visible)
WINDOW_H = PANEL_H + 4.0        # 84
DIFF_T = 3.0                    # opal acrylic thickness
DIFF_OVERLAP = 5.0             # ledge the diffuser rests on, per side
DIFFUSER_W = WINDOW_W + 2 * DIFF_OVERLAP   # 444
DIFFUSER_H = WINDOW_H + 2 * DIFF_OVERLAP   # 94
RECESS = 1.0                   # diffuser sits 1 mm recessed, glued into the rebate
LED_GAP = 8.0                  # air gap LEDs -> diffuser for even glow
FRAME_D = RECESS + DIFF_T + LED_GAP        # 12, front frame depth

# Raspberry Pi 5: 85 x 56, holes 58 x 49, M2.5. Hangs from the rear inner wall.
PI_HOLE_DX, PI_HOLE_DZ = 58.0, 49.0
PI_CENTER = (95.0, 55.0)                       # (x, z) on the rear wall

# Carrier board (pcb/): 150x92, mount holes 136x78. MUST match pcb/place-board.py.
CARR_BOARD_W, CARR_BOARD_H = 150.0, 92.0
CARR_HOLE_DX, CARR_HOLE_DZ = 136.0, 78.0
CARR_CENTER = (-105.0, 55.0)            # board centre on the rear wall (x, z)

# Mounting bosses (M2.5 brass insert or self-tapping; verify pilot).
BOSS_OD = 8.0
BOSS_H = 8.0
BOSS_HOLE = 2.2

# Ceiling-mount ears ("Nasen") on the side walls (+/-X): a pad that ramps out of
# the wall (cast look, not a tacked-on tab), 2 per side, with a vertical screw hole.
EAR_L = 24.0           # sideways protrusion (X)
EAR_W = 28.0           # width along the depth (Y)
EAR_T = 6.0            # pad thickness (Z)
EAR_HOLE = 5.5         # M5 ceiling screw clearance
EAR_INSET = 12.0       # from the front/back edge to the ear
RAMP_H = 22.0          # how far the cast ramp reaches down the wall

# Buttons + encoder in the -X end wall (side): a vertical column. The end wall
# has clear space behind it and is open during assembly (split at X=0), so the
# buttons are easy to fit and wire. Rear wall is blocked by the boards.
BTN_D = 12.0
ENC_D = 7.0
CTRL_Z0 = 22.0         # z of the lowest control
CTRL_PITCH = 18.0      # spacing along Z

# Status/effect LEDs and vents in the rear (-Y) wall.
STATUS_LED_D = 5.0
STATUS_N = 4
STATUS_Z = 90.0
VENT_L, VENT_H = 40.0, 4.0
VENT_COUNT = 6
VENT_Z = 55.0

# Power inlet: Amass XT60E-M panel-mount on the rear wall (external PSU box next to
# the hub, short 5 V jumper plugs in here). Per datasheet: body cutout ~16 x 9,
# 2x M3 holes (d3.2) at ~14 mm vertical spacing. Verify/adjust to the real part.
PWR_CUT_W, PWR_CUT_H = 16.0, 9.0
PWR_SCREW_D = 3.2
PWR_SCREW_DZ = 14.0
PWR_POS = (190.0, 30.0)

# Sensor openings in the bottom (-Z) face (looking down at the terrace).
# Camera Module 3 (standard) per official mechanical drawing: board 25 x 23.862,
# holes d2.2, spacing ~14.4 x 12.5 (asymmetric). The lens-to-hole offset is not
# clearly given in the drawing (RPi forum confirms), so the lens hole is oversized
# and CAM_POS marks the hole-pattern centre; verify against the real part or glue.
CAM_LENS_D = 12.0
CAM_HOLE_DX, CAM_HOLE_DY = 14.4, 12.5
CAM_POS = (70.0, 45.0)
CAM_BOSS_OD, CAM_BOSS_H = 6.0, 6.0
RADAR_MEMBRANE = 2.0                     # thinned wall the LD2410B sees through
RADAR_AREA = 26.0
RADAR_POS = (140.0, 49.0)
MIC_D = 4.0
MIC_POS = (205.0, 49.0)

# Split + dowel posts on the rear inner wall.
DOWEL_D = 4.0
POST_L, POST_DEPTH, POST_H = 16.0, 10.0, 10.0

# Raised slogans: short end walls + bottom face.
TEXT_RIGHT = "HagiOne"          # +X end
TEXT_LEFT = "Balkon Borg"       # -X end
TEXT_SIZE = 14.0
TEXT_DEPTH = 1.5
TEXT_BOTTOM = "Balkon Borg"     # -Z bottom, on the button-free left half
BOTTOM_SIZE = 24.0
BOTTOM_X = -110.0

EPS = 0.1
TOL = 0.4               # SLS/PA12 clearance for fits (holes, pocket, dowels)
CORNER_R = 6.0         # rounded vertical corners (SLS lets us; premium look)

# Ear gussets (triangular ribs under the ceiling ears for strength).
GUSSET_L = 14.0        # how far the rib reaches along the ear
GUSSET_H = 16.0        # how far it runs down the wall

# LED panel locating nubs on the frame back (panel glues between them).
PANEL_BOARD_W = PANEL_W + 8.0          # 438, board slightly larger than pixels
PANEL_BOARD_H = PANEL_H + 8.0          # 88
NUB = 4.0              # nub size
NUB_H = 2.5            # nub protrusion into the cavity

# ---- Review fixes (fasteners, serviceable front, vents, mounts) -------------
INSERT_M25 = 3.4       # heat-set insert hole for M2.5 (Pi, carrier, front bezel)
INSERT_M3 = 4.0        # heat-set insert hole for M3 (seam clamps)
CLR_M3 = 3.4           # M3 clearance hole

# Seam clamp blocks on the rear wall straddling X=0: clearance on -X, insert +X.
SEAM_BLOCK_L = 22.0    # length across the seam (X)
SEAM_BLOCK_H = 14.0    # height (Z)
SEAM_Z = (28.0, 82.0)  # z heights of the rear seam clamps

# Front is open: the diffuser + LED panel are glued into the frame rebate (no bezel).

# Narrow insect-resistant vent slits.
VENT_SLIT = 2.0        # slit width (was 4 mm)
VENT_MID_X = 20.0      # rear vents in the clear zone between carrier and Pi
VENT_END_Z = 100.0     # exhaust slits high on the end walls

# Rear-wall layout. The boards behind the wall define keep-out zones for anything that
# cuts THROUGH the wall (grille, holes). Raised text sits on the OUTSIDE and may go
# anywhere there is wall. Nothing crosses the X=0 split seam, and everything is centred
# in its own zone. SLS prints the honeycomb without supports; webs stay above 1 mm.
HEX_PITCH = 12.0       # hexagon centre-to-centre (across flats)
HEX_WALL = 2.2         # solid web between openings (SLS-safe, > 1 mm)

# Honeycomb grille panels (cx, cz, w, h), each fully inside a board-free zone and on
# one side of the seam: far left of the carrier, the middle bay right of the seam, and
# the wide-flat strips above and below the Pi.
REAR_GRILLES = (
    (-203.0, 55.0, 32.0, 84.0),
    (  29.0, 55.0, 32.0, 84.0),
    (  96.0, 93.0, 82.0, 14.0),
    (  96.0, 16.0, 82.0, 14.0),
)
# Raised wordmarks (text, cx, cz, size), each centred in one half, clear of the seam.
REAR_TEXTS = (
    ("HagiOne",     -115.0, 55.0, 22.0),
    ("Balkon Borg",  115.0, 55.0, 16.0),
)

# WLED controller cradle on the top inner wall. Athom publishes NO mechanical
# dimensions and the High-Power board has no documented mount holes, so this is a
# generous friction/zip-tie pocket. ESTIMATE (verify against the real board):
WLED_BOARD_W, WLED_BOARD_L = 66.0, 44.0   # board footprint (X x Y), estimate
WLED_WALL = 3.0
WLED_POST_H = 10.0
WLED_CENTER = (-30.0, 55.0)          # (x, y) on the top inner wall

# Radar + mic holders and BME280 ambient opening on the bottom face.
RADAR_MNT_DX = 38.0                  # boss spacing flanking the radar membrane
MIC_HOLDER = (205.0, 49.0)          # near the mic hole
BME_POS = (-205.0, 49.0)            # (x, y) ambient opening + mount on the bottom
BME_MESH_DX, BME_MESH_DY = 12.0, 12.0   # small vent grid to outside air
BME_HOLE_DX = 16.0                  # BME280 breakout mount spacing (VERIFY)

# Low divider ribs to organise the cavity ("Trenner").
DIV_H = 22.0           # rib height off the rear wall
DIV_X = (-25.0, 48.0)  # ribs separating carrier | middle | Pi bays

# Derived outer size
OUT_W = PANEL_W + 2 * BORDER            # X (460)
OUT_Z = PANEL_H + 2 * BORDER            # Z (110)
OUT_Y = DEPTH + WALL                    # Y (78), front open
CTRL_Y = OUT_Y / 2                      # control column at mid depth on the end

BUILD = Path(__file__).parent / "build"


def _pattern(center: tuple[float, float], dx: float, dz: float
             ) -> list[tuple[float, float]]:
    cx, cz = center
    return [(cx + sx * dx / 2, cz + sz * dz / 2)
            for sx in (-1, 1) for sz in (-1, 1)]


def _cyl(d: float, h: float, pnt: cq.Vector, direction: cq.Vector) -> cq.Solid:
    return cq.Solid.makeCylinder(d / 2, h, pnt, direction)


def _rear_text(body: cq.Workplane, s: str, cx: float, cz: float,
               size: float, depth: float) -> cq.Workplane:
    """Raise text on the rear (-Y) outer face, exactly centred at (cx, cz).

    Uses a ProjectedOrigin workplane so the text lands where asked instead of at the
    face bounding-box centre (which drifts as features are added).
    """
    return (body.faces("<Y")
            .workplane(centerOption="ProjectedOrigin", origin=(cx, 0.0, cz))
            .text(s, size, depth, combine=True, kind="bold"))


def _hex_grille(cx: float, cz: float, w: float, h: float, pitch: float,
                web: float, ylo: float, yhi: float) -> cq.Compound:
    """A field of pointy-top hexagonal through-holes for a rear vent grille.

    Returns one compound of hex prisms (spanning y = ylo..yhi) to cut in a single
    boolean op. Openings are `pitch - web` across the flats, leaving a uniform `web`
    between neighbours. Cells whose opening would poke past the field are dropped,
    giving a clean rectangular field with a naturally stepped honeycomb border.
    """
    af = pitch - web                      # opening across-flats
    r = af / math.sqrt(3.0)               # circumradius (also vertical half-extent)
    half_w, half_h = af / 2.0, r
    x0, x1 = cx - w / 2.0, cx + w / 2.0
    z0, z1 = cz - h / 2.0, cz + h / 2.0
    dy = pitch * math.sqrt(3.0) / 2.0     # row spacing
    prisms: list[cq.Solid] = []
    z, row = z0 + half_h, 0
    while z <= z1 - half_h + EPS:
        x = x0 + half_w + (pitch / 2.0 if row % 2 else 0.0)
        while x <= x1 - half_w + EPS:
            pts = [cq.Vector(x + r * math.sin(math.radians(60 * i)), ylo,
                             z + r * math.cos(math.radians(60 * i))) for i in range(6)]
            face = cq.Face.makeFromWires(cq.Wire.makePolygon(pts + [pts[0]]))
            prisms.append(cq.Solid.extrudeLinear(face, cq.Vector(0, yhi - ylo, 0)))
            x += pitch
        z += dy
        row += 1
    return cq.Compound.makeCompound(prisms)


def build_body() -> cq.Workplane:
    body = (cq.Workplane("XY")
            .box(OUT_W, OUT_Y, OUT_Z, centered=(True, False, False))
            .edges("|Z or |Y").fillet(CORNER_R))  # round vertical corners + long edges
    # Hollow it with an open front by cutting the inner cavity. (A shell AFTER
    # filleting fails to hollow in OCC and returns a solid block, so cut instead.)
    body = body.cut(cq.Solid.makeBox(
        OUT_W - 2 * WALL, OUT_Y - WALL + EPS, OUT_Z - 2 * WALL,
        cq.Vector(-(OUT_W / 2 - WALL), WALL, WALL)))

    # Front frame: light window, diffuser rebate, and a face to glue the panel.
    zw = (OUT_Z - WINDOW_H) / 2
    frame = cq.Solid.makeBox(OUT_W, FRAME_D, OUT_Z,
                             cq.Vector(-OUT_W / 2, OUT_Y - FRAME_D, 0))
    win = cq.Solid.makeBox(WINDOW_W, FRAME_D + 2 * EPS, WINDOW_H,
                           cq.Vector(-WINDOW_W / 2, OUT_Y - FRAME_D - EPS, zw))
    body = body.union(frame.cut(win))
    zd = (OUT_Z - DIFFUSER_H) / 2
    body = body.cut(cq.Solid.makeBox(
        DIFFUSER_W + TOL, RECESS + DIFF_T + EPS, DIFFUSER_H + TOL,
        cq.Vector(-(DIFFUSER_W + TOL) / 2, OUT_Y - (RECESS + DIFF_T), zd - TOL / 2)))

    # LED panel locating nubs at the board corners on the frame back.
    zp = OUT_Z / 2
    for sx in (1, -1):
        for sz in (1, -1):
            nx = sx * (PANEL_BOARD_W / 2 + TOL + NUB / 2)
            nz = zp + sz * (PANEL_BOARD_H / 2 + TOL + NUB / 2)
            body = body.union(cq.Solid.makeBox(
                NUB, NUB_H, NUB,
                cq.Vector(nx - NUB / 2, OUT_Y - FRAME_D - NUB_H, nz - NUB / 2)))

    # Bosses on the rear inner wall (y=WALL) for Pi 5 and carrier, extending +Y.
    # Holes sized for M2.5 heat-set brass inserts (robust, re-openable).
    for x, z in _pattern(PI_CENTER, PI_HOLE_DX, PI_HOLE_DZ) + \
            _pattern(CARR_CENTER, CARR_HOLE_DX, CARR_HOLE_DZ):
        body = body.union(_cyl(BOSS_OD, BOSS_H, cq.Vector(x, WALL, z), cq.Vector(0, 1, 0)))
        body = body.cut(_cyl(INSERT_M25, BOSS_H + 2 * EPS,
                             cq.Vector(x, WALL - EPS, z), cq.Vector(0, 1, 0)))

    # Seam clamps: blocks straddling X=0 on the rear wall, clearance on the -X half
    # and an M3 insert on the +X half, so the two halves bolt together (driven from
    # the open front during assembly). Dowel posts still handle alignment.
    for z in SEAM_Z:
        body = body.union(cq.Solid.makeBox(
            SEAM_BLOCK_L, POST_DEPTH, SEAM_BLOCK_H,
            cq.Vector(-SEAM_BLOCK_L / 2, WALL, z - SEAM_BLOCK_H / 2)))
        yc = WALL + POST_DEPTH / 2
        body = body.cut(_cyl(CLR_M3, SEAM_BLOCK_L / 2 + EPS,       # -X clearance
                             cq.Vector(-SEAM_BLOCK_L / 2 - EPS, yc, z), cq.Vector(1, 0, 0)))
        body = body.cut(_cyl(INSERT_M3, SEAM_BLOCK_L / 2 + EPS,    # +X insert
                             cq.Vector(0, yc, z), cq.Vector(1, 0, 0)))

    # Dowel posts straddling the split, top and bottom, on the rear inner wall.
    for z in (OUT_Z - BORDER, BORDER):
        body = body.union(cq.Solid.makeBox(
            POST_L, POST_DEPTH, POST_H,
            cq.Vector(-POST_L / 2, WALL, z - POST_H / 2)))
        body = body.cut(_cyl(DOWEL_D + TOL, POST_L + 2 * EPS,
                             cq.Vector(-POST_L / 2 - EPS, WALL + POST_DEPTH / 2, z),
                             cq.Vector(1, 0, 0)))

    # Buttons + encoder as a vertical column in the -X end wall.
    n = 5
    for i in range(n):
        cz = CTRL_Z0 + i * CTRL_PITCH
        d = ENC_D if i == n - 1 else BTN_D
        body = body.cut(_cyl(d + TOL, WALL + 2 * EPS,
                             cq.Vector(-OUT_W / 2 - EPS, CTRL_Y, cz), cq.Vector(1, 0, 0)))

    # Rear (-Y) wall: status LEDs, cable gland, ventilation slots.
    for i in range(STATUS_N):
        sx = 150.0 + i * 20.0          # right side, clear of the carrier board
        body = body.cut(_cyl(STATUS_LED_D, WALL + 2 * EPS,
                             cq.Vector(sx, -EPS, STATUS_Z), cq.Vector(0, 1, 0)))
    px, pz = PWR_POS
    body = body.cut(cq.Solid.makeBox(
        PWR_CUT_W, WALL + 2 * EPS, PWR_CUT_H,
        cq.Vector(px - PWR_CUT_W / 2, -EPS, pz - PWR_CUT_H / 2)))
    for s in (-1, 1):
        body = body.cut(_cyl(PWR_SCREW_D, WALL + 2 * EPS,
                             cq.Vector(px, -EPS, pz + s * PWR_SCREW_DZ / 2),
                             cq.Vector(0, 1, 0)))
    # Hex honeycomb grille panels filling the board-free rear zones (see REAR_GRILLES).
    for cx, cz, w, h in REAR_GRILLES:
        body = body.cut(_hex_grille(cx, cz, w, h, HEX_PITCH, HEX_WALL, -EPS, WALL + EPS))
    # Exhaust: slits high on both end walls (hot air rises; the top is ceiling).
    for sx in (1, -1):
        for z in (VENT_END_Z, VENT_END_Z + 4):
            body = body.cut(cq.Solid.makeBox(
                WALL + 2 * EPS, 44.0, VENT_SLIT,
                cq.Vector(sx * OUT_W / 2 - (WALL + 2 * EPS) * (sx > 0),
                          OUT_Y / 2 - 22, z - VENT_SLIT / 2)))

    # Sensor openings in the bottom (-Z) face, looking down at the terrace.
    cx, cy = CAM_POS
    body = body.cut(_cyl(CAM_LENS_D, WALL + 2 * EPS,
                         cq.Vector(cx, cy, -EPS), cq.Vector(0, 0, 1)))
    for bx, by in _pattern(CAM_POS, CAM_HOLE_DX, CAM_HOLE_DY):
        body = body.union(_cyl(CAM_BOSS_OD, CAM_BOSS_H,
                               cq.Vector(bx, by, WALL), cq.Vector(0, 0, 1)))
        body = body.cut(_cyl(2.2, CAM_BOSS_H + 2 * EPS,
                             cq.Vector(bx, by, WALL - EPS), cq.Vector(0, 0, 1)))
    rx, ry = RADAR_POS
    body = body.cut(cq.Solid.makeBox(
        RADAR_AREA, RADAR_AREA, WALL - RADAR_MEMBRANE + EPS,
        cq.Vector(rx - RADAR_AREA / 2, ry - RADAR_AREA / 2, RADAR_MEMBRANE)))
    mx, my = MIC_POS
    body = body.cut(_cyl(MIC_D, WALL + 2 * EPS, cq.Vector(mx, my, -EPS), cq.Vector(0, 0, 1)))

    def _boss_z(x: float, y: float, h: float, hole: float) -> None:
        nonlocal body
        body = body.union(_cyl(6.0, h, cq.Vector(x, y, WALL), cq.Vector(0, 0, 1)))
        body = body.cut(_cyl(hole, h + 2 * EPS, cq.Vector(x, y, WALL - EPS), cq.Vector(0, 0, 1)))

    # Radar + mic holders on the bottom (module sits on the bosses, wired to J_*).
    for s in (-1, 1):
        _boss_z(rx + s * RADAR_MNT_DX / 2, ry, 6.0, 2.0)
    mhx, mhy = MIC_HOLDER
    _boss_z(mhx, mhy + 10, 6.0, 2.0)

    # BME280 ambient opening + mount on the bottom, so it reads OUTSIDE air.
    bx, by = BME_POS
    for gx in (-4.0, 0.0, 4.0):
        for gy in (-4.0, 0.0, 4.0):
            body = body.cut(_cyl(2.0, WALL + 2 * EPS,
                                 cq.Vector(bx + gx, by + gy, -EPS), cq.Vector(0, 0, 1)))
    for s in (-1, 1):
        _boss_z(bx + s * BME_HOLE_DX / 2, by, 6.0, 2.0)

    # WLED controller cradle on the top inner wall: a pocket the board drops into,
    # open on the +Y side for cables; final retention by a zip-tie. Size-tolerant.
    wcx, wcy = WLED_CENTER
    pw, pl = WLED_BOARD_W + 2 * TOL, WLED_BOARD_L + 2 * TOL
    zbot = OUT_Z - WALL - WLED_POST_H
    cradle = cq.Solid.makeBox(
        pw + 2 * WLED_WALL, pl + 2 * WLED_WALL, WLED_POST_H,
        cq.Vector(wcx - pw / 2 - WLED_WALL, wcy - pl / 2 - WLED_WALL, zbot))
    cradle = cradle.cut(cq.Solid.makeBox(
        pw, pl, WLED_POST_H + EPS, cq.Vector(wcx - pw / 2, wcy - pl / 2, zbot - EPS)))
    cradle = cradle.cut(cq.Solid.makeBox(       # open the cable side (+Y)
        pw, WLED_WALL + 2 * EPS, WLED_POST_H,
        cq.Vector(wcx - pw / 2, wcy + pl / 2, zbot)))
    body = body.union(cradle)

    # Low divider ribs on the rear wall: carrier | middle (WLED/SDR/wiring) | Pi.
    for dx in DIV_X:
        body = body.union(cq.Solid.makeBox(
            3.0, DIV_H, OUT_Z - 2 * BORDER,
            cq.Vector(dx - 1.5, WALL, BORDER)))

    # Ceiling-mount ears on the +/-X side walls, ramping out of the wall (cast look).
    for sx in (1, -1):
        wall = sx * OUT_W / 2
        outer = sx * EAR_L
        for yc in (EAR_INSET + EAR_W / 2, OUT_Y - EAR_INSET - EAR_W / 2):
            # profile in X-Z: flat pad on top blending into a ramp down the wall
            pts = [(wall, OUT_Z),
                   (wall + outer, OUT_Z),
                   (wall + outer, OUT_Z - EAR_T),
                   (wall, OUT_Z - EAR_T - RAMP_H)]
            ear = (cq.Workplane("XZ").polyline(pts).close()
                   .extrude(-EAR_W).translate((0, yc - EAR_W / 2, 0)))
            body = body.union(ear)
            body = body.cut(_cyl(EAR_HOLE, EAR_T + 2 * EPS,
                                 cq.Vector(wall + outer / 2, yc, OUT_Z - EAR_T - EPS),
                                 cq.Vector(0, 0, 1)))

    # Raised slogans: HagiOne on the +X end (the -X end now holds the buttons),
    # Balkon Borg on the bottom.
    body = (body.faces(">X").workplane(centerOption="CenterOfBoundBox")
            .text(TEXT_RIGHT, TEXT_SIZE, TEXT_DEPTH, combine=True))
    body = (body.faces("<Z").workplane(centerOption="CenterOfBoundBox")
            .center(BOTTOM_X, 0).text(TEXT_BOTTOM, BOTTOM_SIZE, TEXT_DEPTH, combine=True))
    # Rear wordmarks, each centred in its half (see REAR_TEXTS), clear of the seam.
    for s, cx, cz, size in REAR_TEXTS:
        body = _rear_text(body, s, cx, cz, size, TEXT_DEPTH)

    # Trim any boolean sliver above the ceiling plane so the ear tops stay flat.
    body = body.cut(cq.Solid.makeBox(
        3 * OUT_W, 3 * (OUT_Y + EAR_L), 60,
        cq.Vector(-1.5 * OUT_W, -1.5 * (OUT_Y + EAR_L), OUT_Z)))
    return body


def split_halves(body: cq.Workplane) -> tuple[cq.Workplane, cq.Workplane]:
    big = (OUT_W + 2 * EAR_L, 2 * (OUT_Y + EAR_L), 2 * OUT_Z)
    left = cq.Solid.makeBox(*big, cq.Vector(-(OUT_W + 2 * EAR_L), -(OUT_Y + EAR_L), -OUT_Z / 2))
    right = cq.Solid.makeBox(*big, cq.Vector(0, -(OUT_Y + EAR_L), -OUT_Z / 2))
    return body.intersect(left), body.intersect(right)


def main() -> int:
    BUILD.mkdir(exist_ok=True)
    body = build_body()
    left, right = split_halves(body)
    for name, shape in {"balkon-borg-body": body,
                        "balkon-borg-left": left,
                        "balkon-borg-right": right}.items():
        cq.exporters.export(shape, str(BUILD / f"{name}.step"))
        cq.exporters.export(shape, str(BUILD / f"{name}.stl"))
        print(f"wrote {name}.step / .stl")
    print(f"outer size (W x D x H): {OUT_W:.0f} x {OUT_Y:.0f} x {OUT_Z:.0f} mm")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

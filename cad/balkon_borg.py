#!/usr/bin/env python3
"""Parametric enclosure for the Balkon-Borg (CadQuery).

Ceiling-mounted under the balcony, LED panel facing FORWARD to the terrace.
Orientation in this model:

    X  = width (along the 43-pixel panel columns)
    Z  = up (toward the ceiling); +Z top wall, -Z bottom
    Y  = depth (front to back); +Y = front/terrace (OPEN light window),
         -Y = rear/house

Faces and their jobs (pre-mirror; MIRROR flips left/right):
    +Y front  : LED panel + diffuser in the open light window (light forward).
                Stays text-free.
    -Z bottom : camera pod, LED indicator tower (with the radar), speaker
                grille, BME opening, drains, big raised wordmarks.
    -Y rear   : status LEDs, XT60 power inlet, honeycomb vents, wordmarks.
    +Z top    : ceiling side; lateral ears ("Nasen") with vertical screw holes,
                screwed up into the ceiling from below; big service opening.
    +X end    : honeycomb grille + SMA antenna hole (Pi/SDR side).
    -X end    : 2x2 buttons + encoder.

The Pi 5 and the sensor carrier hang from the rear inner wall on bosses. Split at
X=0 into two halves for the print bed, aligned by 4 mm dowel pins in posts and
bolted with the internal M3 seam clamps.

Dimensions are datasheet-derived with generous clearances (see PARAMETERS). The
LED panel size is an assumption (10 mm pitch) and drives the overall size.

Run: python balkon_borg.py   ->   writes STEP and STL into build/.

The camera looks FORWARD (not down): it hangs in a downward box (open at the top into the
cavity), +X side near the Pi, set back in the rear quarter so nothing protrudes past the
front face (see _camera_pod). CSI reaches (measured cable ~240 mm).
"""

from __future__ import annotations

import math
from pathlib import Path

import cadquery as cq

# ---- PARAMETERS (mm) --------------------------------------------------------

# LED light field. The window/front is sized for a 430 x 80 mm field (historic plan:
# 43 x 8 at 10 mm pitch). The REAL build is 8 rows of SK6812 RGBWW strip (60 LEDs/m,
# 10 mm wide PCB, rows edge to edge), 25 LEDs per row = ~417 x 80 mm pixel field,
# centred on an aluminium plate CUT TO ORDER at exactly PANEL_BOARD_W/H below - so the
# plate dimension is a purchase spec, not an assumption. These anchors stay: they set
# the window and the outer size of the (already ordered) enclosure.
PANEL_COLS = 43
PANEL_ROWS = 8
PANEL_PITCH = 10.0
PANEL_W = PANEL_COLS * PANEL_PITCH            # 430 (X)
PANEL_H = PANEL_ROWS * PANEL_PITCH            # 80  (Z)

BORDER = 15.0            # frame around the front light window
WALL = 3.0              # PA12 (SLS) wall thickness
DEPTH = 145.0           # internal depth front-to-back (Y); +50 mm over the original
                        # 95 gives generous room and ~55 mm WLED-to-LED clearance

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
FOOT_W = 2.0           # tapered foot flare at boss/clamp bases (softens the abrupt
FOOT_H = 2.5           # 3 mm-wall -> block transition; reduces stress/sink/warp)

# Ceiling-mount ears ("Nasen") on the side walls (+/-X): a pad that ramps out of
# the wall (cast look, not a tacked-on tab), 2 per side, with a vertical screw hole.
EAR_L = 24.0           # sideways protrusion (X)
EAR_W = 28.0           # width along the depth (Y)
EAR_T = 6.0            # pad thickness (Z)
EAR_HOLE = 5.5         # M5 ceiling screw clearance (through-hole, top to underside)
EAR_CB_D = 11.0        # counterbore for the M5 head: a flat seat on the sloped underside
EAR_INSET = 12.0       # from the front/back edge to the ear
RAMP_H = 40.0          # how far the cast blend sweeps down the wall (concave, organic)
EAR_EDGE_R = 6.0       # soften the ear's outer edges so it flows into the wall

# Buttons + encoder in the -X end wall (side): a vertical column. The end wall
# has clear space behind it and is open during assembly (split at X=0), so the
# buttons are easy to fit and wire. Rear wall is blocked by the boards.
BTN_D = 12.0
ENC_D = 7.0
# 4 buttons in a 2x2 rectangle on the -X end wall (two depth columns Y x two rows Z),
# generously spaced (big fingers), plus the encoder above the top-right button.
BTN_COLS_Y = (56.0, 92.0)      # button depth columns (Y)
BTN_ROWS_Z = (29.0, 61.0)      # button height rows (Z) — shifted 5 mm down
ENC_Z = 91.0                   # encoder above the top row (5 mm down, off the top edge)

# Status/effect LEDs in the rear (-Y) wall (5 mm LED body + clearance, like LED_HOLE_D).
STATUS_LED_D = 5.2
STATUS_N = 4
STATUS_Z = 90.0

# Power inlet: Amass XT60E-M panel-mount on the rear wall (external PSU box next to
# the hub, short 5 V jumper plugs in here). Per datasheet: body cutout ~16 x 9,
# 2x M3 holes (d3.2) at ~14 mm vertical spacing. Verify/adjust to the real part.
PWR_CUT_W, PWR_CUT_H = 16.0, 9.0
PWR_SCREW_D = 3.2
PWR_SCREW_DZ = 14.0
PWR_POS = (190.0, 30.0)

# Camera Module 3 (STANDARD, the one bought) per the official mechanical drawing: board
# 25 x 23.862, the lens stack protrudes 6.98 mm above the board (base plate to 2.75,
# lens block to 3.875, barrel to the tip at 6.98). It looks FORWARD to the terrace,
# slightly down, hanging in a downward box (open at the top into the cavity), +X side
# near the Pi, set back so it does NOT protrude past the front face. The whole FRONT
# WALL of the box is TILTED (a flat plane perpendicular to the view axis). Mounting is
# HOT GLUE: the lens block presses flat against the inside of that wall, the barrel
# passes through the bore (~0.6 mm proud outside, so nothing can vignette) and the board
# corners are tacked with hot glue. No screw holes: the real hole pattern is 21.0 x 12.5
# (holes 2.0 off the board edges, lens ON the top row), useless in a 2.5 mm wall without
# standoffs.
CAM_TILT_DOWN = 24.0         # front-wall tilt below horizontal. Standard lens: 41 deg
                             # vertical FOV, so the view spans 3.5..44.5 deg below
                             # horizontal (own housing trivially out of frame; the limit
                             # for a wider lens is a top ray <= ~11.8 deg above horizon).
CAM_CX = 75.0                # box centre X (pre-mirror; +X/Pi side, near the Pi)
CAM_BOX_W = 54.0             # box width (X) — another 1 cm roomier
CAM_BOX_BACK_Y = 22.0        # back wall (Y); the tilted front wall is derived from the lens
CAM_BOX_DROP = 42.0          # how far it hangs below the bottom wall (-Z)
CAM_BOX_WALL = 2.5           # box side/back/floor walls
CAM_WIN_WALL = 2.5           # flat tilted front wall (also gives the board screws purchase)
CAM_LENS_Y = 52.0            # lens centre on the front wall, outer face (Y at CAM_LENS_Z)
CAM_LENS_Z = -20.0           # lens centre height (below the bottom, mid of the hang)
CAM_LENS_D = 9.0             # lens bore (barrel d6.95 + clearance; block seats inside)
CAM_CHAMFER_D = 14.0         # outer lens opening (widens outward)
CAM_DRAIN_D = 4.0            # drain in the pod floor (condensation + powder escape)

# Speaker: Visaton BF 45, a round fullrange (45 mm cutout, ~26 mm deep, 17 mm voice coil).
# Glued to the inside of the bottom wall firing DOWN; a round hex-packed hole grille in the
# floor lets the sound out to the terrace. Sits between the camera box and the -X end (the
# right-hand end seen from the front). Pre-mirror X (mirrors to -X with the camera).
SPK_POS = (180.0, 40.0)      # (x, y) pre-mirror; clear of the wordmark and off the rear wall
SPK_GRILLE_D = 44.0          # grille field diameter (matches the BF 45 cone/cutout)
SPK_HOLE_D = 3.5             # grille hole diameter
SPK_HOLE_PITCH = 6.0         # hex-packing pitch

# Split + dowel posts on the rear inner wall.
DOWEL_D = 4.0
POST_L, POST_DEPTH, POST_H = 16.0, 10.0, 10.0

# Raised wordmarks: rear wall (REAR_TEXTS) + bottom face.
TEXT_DEPTH = 1.5
TEXT_BOTTOM = "Balkon Borg"     # -Z bottom brand plate (faces the terrace below)
BOTTOM_SIZE = 48.0              # doubled; big Balkon Borg on the underside
BOTTOM_HG_SIZE = 18.0           # small HagiOne beside it
BB_POS = (25.0, 98.0)          # Balkon Borg centre (x, y), shifted right to clear the tower
HG_POS = (-5.0, 60.0)          # small HagiOne, shifted 30 mm toward the other side (away
                               # from the camera box) so it clears it on the underside

EPS = 0.1
TOL = 0.5               # SLS/PA12 clearance for fits (holes, pocket, dowels) — mid of
                        # the SLS range, not the 0.4 low limit (dowels/diffuser fit)
CORNER_R = 12.0        # rounded vertical corners + bottom edges (organic; top stays flat)
RIB_W, RIB_H = 3.0, 8.0   # internal stiffening ribs against long-panel warp (bottom wall)
RIB_X = (-95.0, -40.0, 40.0, 110.0)  # rib X positions, clear of tower/camera box/drain
                                     # (the 54 mm camera box spans x 48..102: 110, not 95)
MIRROR = True          # full left/right (X) mirror: swaps the busy +X side (Pi/SDR,
                       # camera/radar/mic) with the quiet -X side (buttons, LED tower)

# LED panel locating nubs on the frame back (panel glues between them).
PANEL_BOARD_W = PANEL_W + 8.0          # 438: the alu plate, bought cut to this size
PANEL_BOARD_H = PANEL_H + 8.0          # 88
NUB = 4.0              # nub size
NUB_H = 2.5            # nub protrusion into the cavity
NUB_CLR = 1.0          # play around the plate: sheet blanks are cut to +/-1 mm, more
                       # than the print TOL - the nubs only locate, the glue holds

# ---- Review fixes (fasteners, serviceable front, vents, mounts) -------------
INSERT_M25 = 3.4       # heat-set insert hole for M2.5 (Pi, carrier, front bezel)
INSERT_M3 = 4.0        # heat-set insert hole for M3 (seam clamps)
CLR_M3 = 3.4           # M3 clearance hole

# Seam clamp blocks on the rear wall straddling X=0: clearance on -X, insert +X.
SEAM_BLOCK_L = 22.0    # length across the seam (X)
SEAM_BLOCK_H = 14.0    # height (Z)
FRONT_SEAM_Y = 115.0   # a seam clamp near the open front (bottom wall), so the deep
                       # front edges of the two halves cannot gap before gluing
SEAM_Z = (28.0, 82.0)  # z heights of the rear seam clamps

# Front is open: the diffuser + LED panel are glued into the frame rebate (no bezel).

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
# Raised wordmarks (text, cx, cz, size); pre-mirror X (build multiplies by sx). Swapped
# sides: HagiOne one half, the now-doubled Balkon Borg the other, both clear of the seam
# (Balkon Borg at 32 is ~182 mm wide, tucked between the seam and the side grille).
REAR_TEXTS = (
    ("HagiOne",      115.0, 55.0, 22.0),
    ("Balkon Borg",  -93.0, 55.0, 32.0),
)
# Honeycomb grille centred on the +X end wall (replaces the old floating HagiOne and
# the side exhaust slits). In-plane (cy, cz, w=depth Y, h=height Z), below the ears.
END_GRILLE = (74.0, 45.0, 92.0, 58.0)
# SDR antenna: SMA bulkhead panel-mount hole in the SDR-side end wall (same wall as the
# grille). 6.5 mm round; a short SMA pigtail inside runs to the SDR, antenna screws on
# outside. Placed front of the grille, mid-height, clear of grille and front frame.
ANT_HOLE_D = 6.5
ANT_POS = (128.0, 45.0)   # (y, z) on the end wall

# WLED controller cradle on the top inner wall. Athom publishes NO mechanical
# dimensions and the High-Power board has no documented mount holes, so this is a
# generous friction/zip-tie pocket. ESTIMATE (verify against the real board):
WLED_BOARD_W, WLED_BOARD_L = 66.0, 44.0   # board footprint (X x Y), estimate
WLED_WALL = 3.0
WLED_POST_H = 10.0
WLED_CENTER = (-30.0, 55.0)          # (x, y) on the top inner wall

# Ceiling (+Z) service/vent opening: a big central cut-out. The front panel is glued
# on, so this is the only way back to the internals; it also adds ventilation (warm
# air to the concrete above / out through any gap) and saves material. A solid border
# is kept all round (still lies flat against the ceiling), and the opening is notched
# around the WLED cradle so that pocket keeps its wall and stays attached.
LID_MARGIN = 18.0      # solid border kept around the opening (from the outer edge)
LID_CORNER_R = 12.0    # rounded opening corners (SLS: avoid sharp inside notches)
LID_NOTCH_M = 6.0      # extra material kept around the WLED cradle inside the opening
LID_TONGUE_RIB = 5.0   # extra ceiling-wall thickness under the notch tongue (stiffen it)

# BME280 ambient opening on the bottom face (radar lives in the LED tower, mic on the Pi).
# Breakout boards differ in size and hole spacing by vendor, so no fixed bosses: a
# generous drop-in cradle over the vent grid, open toward -Y (rear/carrier) for the
# cable, the board tacked with hot glue. Fits everything up to BME_POCKET square.
BME_POS = (-205.0, 49.0)            # (x, y) ambient opening + mount on the bottom
BME_POCKET = 26.0                   # cradle inner square
BME_POCKET_H = 8.0                  # cradle wall height
BME_POCKET_WALL = 3.0

# Downward LED indicator tower on the bottom (-Z), left side, centred in depth. A
# hollow 40x40 box protruding 30 mm down; 4 always-on LEDs glue in from inside and a
# cable is fed down from the board's 5 V. Holes sized for 5 mm LEDs (5.2 mm); bump to
# 8.2 for 8 mm LEDs. Kept clear of the corner, the BME opening and the bottom wordmark.
LED_BOX = 40.0                 # bottom (tip) square side
LED_BOX_H = 38.0               # protrusion down (-Z); tall enough to hold the LD2410B
                               # radar (35 mm) behind the front face (see radar note)
LED_BOX_WALL = 3.0
LED_TAPER = 20.0               # draft angle from vertical: wide at top, 40x40 at bottom
LED_BOX_POS = (-155.0, 74.0)   # (x, y) tower axis on the bottom face (left, centred depth)
LED_HOLE_D = 5.2               # 5 mm LED body + clearance (flange seats from inside)
RADAR_WIN_L = 30.0             # radar window in the front (+Y) tower face: a slot the
RADAR_WIN_W = 5.5              # 35x7 LD2410B overlaps all round, glued over it from
                               # inside (seals the tower against insects and holds it)

# Drain holes at the lowest points (ceiling-mounted, bottom faces down): condensation
# runs out, and they double as powder-escape for the tower pocket.
DRAIN_D = 5.0
BOTTOM_DRAIN_POS = (120.0, 25.0)   # a clear bottom spot (pre-mirror), off boards/text

# Low divider ribs to organise the cavity ("Trenner").
DIV_H = 22.0           # rib height off the rear wall
DIV_X = (-25.0, 48.0)  # ribs separating carrier | middle | Pi bays

# Derived outer size
OUT_W = PANEL_W + 2 * BORDER            # X (460)
OUT_Z = PANEL_H + 2 * BORDER            # Z (110)
OUT_Y = DEPTH + WALL                    # Y (148), front open

BUILD = Path(__file__).parent / "build"


def _pattern(center: tuple[float, float], dx: float, dz: float
             ) -> list[tuple[float, float]]:
    cx, cz = center
    return [(cx + sx * dx / 2, cz + sz * dz / 2)
            for sx in (-1, 1) for sz in (-1, 1)]


def _cyl(d: float, h: float, pnt: cq.Vector, direction: cq.Vector) -> cq.Solid:
    return cq.Solid.makeCylinder(d / 2, h, pnt, direction)


def _foot(lu: float, lv: float, origin: tuple[float, float, float],
          normal: tuple[float, float, float]) -> cq.Workplane:
    """A tapered foot to blend a rear/bottom-wall block into the wall (softer transition):
    an (lu+2*FOOT_W) x (lv+2*FOOT_W) base at `origin` tapering to lu x lv over FOOT_H along
    `normal`. Additive (robust) — avoids fragile post-union junction fillets."""
    return (cq.Workplane(cq.Plane(origin=origin, normal=normal, xDir=(1, 0, 0)))
            .rect(lu + 2 * FOOT_W, lv + 2 * FOOT_W)
            .workplane(offset=FOOT_H).rect(lu, lv)
            .loft(combine=False))


def _rear_text(body: cq.Workplane, s: str, cx: float, cz: float,
               size: float, depth: float) -> cq.Workplane:
    """Raise text on the rear (-Y) outer face, exactly centred at (cx, cz).

    Built on an explicit plane at the rear wall (y=0), not `faces("<Y")`: after the
    first wordmark is raised, the lowest-Y face is that glyph, so a second face-based
    call lands its text on the first glyph's plane and floats ~1.5 mm off the wall.
    The explicit plane (like _bottom_text) starts just inside the wall so the text
    fuses cleanly instead of becoming a loose solid.
    """
    pl = cq.Plane(origin=(cx, 0.3, cz), xDir=(1, 0, 0), normal=(0, -1, 0))
    return body.union(cq.Workplane(pl).text(s, size, depth + 0.3, kind="bold"))


def _bottom_text(body: cq.Workplane, s: str, cx: float, cy: float,
                 size: float, depth: float) -> cq.Workplane:
    """Raise text on the bottom (-Z) outer face, readable from below (the terrace).

    Built on an explicit plane with flipped X so the wordmark is not mirrored when
    read from underneath, and centred exactly at (cx, cy).
    """
    pl = cq.Plane(origin=(cx, cy, 0.3), xDir=(-1, 0, 0), normal=(0, 0, -1))
    return body.union(cq.Workplane(pl).text(s, size, depth + 0.3, kind="bold"))


def _hex_grille(u_c: float, v_c: float, w: float, h: float, pitch: float,
                web: float, t0: float, t1: float, axis: str = "y") -> cq.Compound:
    """A field of pointy-top hexagonal through-holes for a vent grille.

    In-plane centre (u_c, v_c) with extents (w, h); the holes go through the wall
    from t0 to t1 along `axis`. axis="y" is an X-Z wall (rear/front), axis="x" is a
    Y-Z wall (the side end walls): then u is depth (Y) and v is height (Z). Returns
    one compound to cut in a single boolean op. Openings are `pitch - web` across the
    flats; cells that would poke past the field are dropped for a clean stepped edge.
    """
    af = pitch - web                      # opening across-flats
    r = af / math.sqrt(3.0)               # circumradius (also vertical half-extent)
    half_u, half_v = af / 2.0, r
    u0, u1 = u_c - w / 2.0, u_c + w / 2.0
    v0, v1 = v_c - h / 2.0, v_c + h / 2.0
    dv = pitch * math.sqrt(3.0) / 2.0     # row spacing

    def pt(a: float, b: float) -> cq.Vector:
        return cq.Vector(a, t0, b) if axis == "y" else cq.Vector(t0, a, b)
    thru = cq.Vector(0, t1 - t0, 0) if axis == "y" else cq.Vector(t1 - t0, 0, 0)

    prisms: list[cq.Solid] = []
    v, row = v0 + half_v, 0
    while v <= v1 - half_v + EPS:
        u = u0 + half_u + (pitch / 2.0 if row % 2 else 0.0)
        while u <= u1 - half_u + EPS:
            pts = [pt(u + r * math.sin(math.radians(60 * i)),
                      v + r * math.cos(math.radians(60 * i))) for i in range(6)]
            face = cq.Face.makeFromWires(cq.Wire.makePolygon(pts + [pts[0]]))
            prisms.append(cq.Solid.extrudeLinear(face, thru))
            u += pitch
        v += dv
        row += 1
    return cq.Compound.makeCompound(prisms)


def _camera_pod(body: cq.Workplane) -> cq.Workplane:
    """Downward-hanging camera box (+X side, pre-mirror), open at the top, WEDGE front.

    The Camera Module 3 looks FORWARD to the terrace, slightly down. The box hangs below
    the bottom wall like the LED tower, set back so nothing protrudes past the front
    face. The whole FRONT WALL is a flat plane tilted CAM_TILT_DOWN (perpendicular to the
    view axis): the lens BLOCK presses flat against its inside, the barrel (~d7) passes
    through the bore and ends ~0.6 mm proud of the outer face (no vignetting), and the
    module is fixed with hot glue at the board corners. The box is OPEN AT THE TOP: the
    hollow runs up through the bottom wall into the cavity, so the camera is fitted from
    the ceiling opening and the CSI routes up to the Pi. A floor drain lets condensation
    out (and powder, after printing).
    """
    t = math.radians(CAM_TILT_DOWN)
    st, ct = math.sin(t), math.cos(t)
    tan_t = st / ct
    n = cq.Vector(0.0, ct, -st)           # outward view normal (forward + down)
    cx, W, wall = CAM_CX, CAM_BOX_W, CAM_BOX_WALL
    hw = W / 2.0
    z_top, z_floor, yb = WALL, -CAM_BOX_DROP, CAM_BOX_BACK_Y

    def wedge(x0: float, width: float, prof: list[tuple[float, float]]) -> cq.Solid:
        pts = [cq.Vector(x0, y, z) for (y, z) in prof]
        face = cq.Face.makeFromWires(cq.Wire.makePolygon(pts + [pts[0]]))
        return cq.Solid.extrudeLinear(face, cq.Vector(width, 0.0, 0.0))

    # Front-wall line through the lens (outer face); the wall tilts, top juts forward.
    def yf_out(z: float) -> float:
        return CAM_LENS_Y + (z - CAM_LENS_Z) * tan_t

    # Outer wedge box: back wall vertical, floor flat, front wall tilted.
    body = body.union(wedge(cx - hw, W, [(yb, z_top), (yf_out(z_top), z_top),
                                         (yf_out(z_floor), z_floor), (yb, z_floor)]))
    # Inner cavity, parallel-offset the front wall inward by CAM_WIN_WALL, inset the other
    # walls, run the top up into the cavity (open top: cuts through the bottom wall).
    yl_in = CAM_LENS_Y - ct * CAM_WIN_WALL            # inner front line, offset along -n
    zl_in = CAM_LENS_Z + st * CAM_WIN_WALL
    def yf_in(z: float) -> float:
        return yl_in + (z - zl_in) * tan_t
    z_hi, zfi = 30.0, z_floor + wall
    body = body.cut(wedge(cx - hw + wall, W - 2 * wall,
                          [(yb + wall, z_hi), (yf_in(z_hi), z_hi),
                           (yf_in(zfi), zfi), (yb + wall, zfi)]))

    # Clean round lens hole, bored straight through the flat tilted wall (widens outward).
    lens_out = cq.Vector(cx, CAM_LENS_Y, CAM_LENS_Z)
    body = body.cut(cq.Solid.makeCone(
        CAM_LENS_D / 2, CAM_CHAMFER_D / 2, CAM_WIN_WALL + 2 * EPS,
        lens_out - n.multiply(CAM_WIN_WALL + EPS), n))
    # Drain in the pod floor (its lowest inner point is a closed tub otherwise).
    body = body.cut(_cyl(CAM_DRAIN_D, wall + 2 * EPS,
                         cq.Vector(cx, yb + 10.0, z_floor - EPS), cq.Vector(0, 0, 1)))
    return body


def _speaker_grille(body: cq.Workplane) -> cq.Workplane:
    """Round hex-packed hole grille in the bottom wall for a down-firing BF 45 speaker."""
    cx, cy = SPK_POS
    R = SPK_GRILLE_D / 2.0
    rlim = R - SPK_HOLE_D / 2.0            # keep whole holes inside the field
    pitch = SPK_HOLE_PITCH
    dv = pitch * math.sqrt(3) / 2.0
    cuts: list[cq.Solid] = []
    v, row = -R, 0
    while v <= R + EPS:
        off = pitch / 2.0 if row % 2 else 0.0
        u = -R + off
        while u <= R + EPS:
            if u * u + v * v <= rlim * rlim:
                cuts.append(_cyl(SPK_HOLE_D, WALL + 2 * EPS,
                                 cq.Vector(cx + u, cy + v, -EPS), cq.Vector(0, 0, 1)))
            u += pitch
        v += dv
        row += 1
    if cuts:
        body = body.cut(cq.Compound.makeCompound(cuts))
    return body


def build_body() -> cq.Workplane:
    body = (cq.Workplane("XY")
            .box(OUT_W, OUT_Y, OUT_Z, centered=(True, False, False))
            # round the vertical corners + bottom side edges (top stays sharp = flat
            # ceiling face); one radius so the bottom corners blend cleanly and organic.
            .edges("|Z or (|Y and <Z)").fillet(CORNER_R))
    # Hollow it with an open front by cutting the inner cavity. (A shell AFTER filleting
    # fails to hollow in OCC, so cut instead.) The cavity is ROUNDED to follow the outer
    # corners (r = CORNER_R - WALL) so the shell stays a uniform WALL thick around the
    # rounding — otherwise a large corner radius eats through the thin wall (a gap/crack).
    cav = (cq.Workplane("XY")
           .box(OUT_W - 2 * WALL, OUT_Y - WALL + EPS, OUT_Z - 2 * WALL,
                centered=(True, False, False))
           .edges("|Z or (|Y and <Z)").fillet(CORNER_R - WALL)
           .translate((0, WALL, WALL)))
    body = body.cut(cav)

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

    # Core the frame border from the back (leave a ~5 mm front skin + 3 mm walls + a
    # surround around the window/nubs) so it is not a solid ~13x12 mm ring — cuts mass,
    # warp/sink and material. Moderate ("nicht zu stark"). The kept block spans past the
    # locating nubs AND the diffuser rebate, so the nubs sit on solid frame back (not on
    # a cored edge) and no ~1 mm skin sliver is left between rebate floor and coring.
    fskin = RECESS + DIFF_T + 1.0
    keep_w = PANEL_BOARD_W + 2 * NUB_CLR + 2 * NUB + 2.0
    keep_h = PANEL_BOARD_H + 2 * NUB_CLR + 2 * NUB + 2.0
    core_outer = cq.Solid.makeBox(
        OUT_W - 2 * WALL, FRAME_D - fskin + EPS, OUT_Z - 2 * WALL,
        cq.Vector(-(OUT_W / 2 - WALL), OUT_Y - FRAME_D - EPS, WALL))
    core_keep = cq.Solid.makeBox(
        keep_w, FRAME_D, keep_h,
        cq.Vector(-keep_w / 2, OUT_Y - FRAME_D - EPS, (OUT_Z - keep_h) / 2))
    body = body.cut(core_outer.cut(core_keep))

    # LED panel locating nubs at the plate corners on the frame back.
    zp = OUT_Z / 2
    for sx in (1, -1):
        for sz in (1, -1):
            nx = sx * (PANEL_BOARD_W / 2 + NUB_CLR + NUB / 2)
            nz = zp + sz * (PANEL_BOARD_H / 2 + NUB_CLR + NUB / 2)
            body = body.union(cq.Solid.makeBox(
                NUB, NUB_H, NUB,
                cq.Vector(nx - NUB / 2, OUT_Y - FRAME_D - NUB_H, nz - NUB / 2)))

    # Bosses on the rear inner wall (y=WALL) for Pi 5 and carrier, extending +Y.
    # Holes sized for M2.5 heat-set brass inserts (robust, re-openable).
    for x, z in _pattern(PI_CENTER, PI_HOLE_DX, PI_HOLE_DZ) + \
            _pattern(CARR_CENTER, CARR_HOLE_DX, CARR_HOLE_DZ):
        body = body.union(_cyl(BOSS_OD, BOSS_H, cq.Vector(x, WALL, z), cq.Vector(0, 1, 0)))
        body = body.union(cq.Solid.makeCone(       # tapered foot into the wall
            BOSS_OD / 2 + FOOT_W, BOSS_OD / 2, FOOT_H, cq.Vector(x, WALL, z), cq.Vector(0, 1, 0)))
        body = body.cut(_cyl(INSERT_M25, BOSS_H + 2 * EPS,
                             cq.Vector(x, WALL - EPS, z), cq.Vector(0, 1, 0)))

    # Seam clamps: blocks straddling X=0 on the rear wall, clearance on the -X half
    # and an M3 insert on the +X half, so the two halves bolt together (driven from
    # the open front during assembly). Dowel posts still handle alignment.
    for z in SEAM_Z:
        body = body.union(cq.Solid.makeBox(
            SEAM_BLOCK_L, POST_DEPTH, SEAM_BLOCK_H,
            cq.Vector(-SEAM_BLOCK_L / 2, WALL, z - SEAM_BLOCK_H / 2)))
        body = body.union(_foot(SEAM_BLOCK_L, SEAM_BLOCK_H, (0, WALL, z), (0, 1, 0)))
        yc = WALL + POST_DEPTH / 2
        body = body.cut(_cyl(CLR_M3, SEAM_BLOCK_L / 2 + EPS,       # -X clearance
                             cq.Vector(-SEAM_BLOCK_L / 2 - EPS, yc, z), cq.Vector(1, 0, 0)))
        body = body.cut(_cyl(INSERT_M3, SEAM_BLOCK_L / 2 + EPS,    # +X insert
                             cq.Vector(0, yc, z), cq.Vector(1, 0, 0)))

    # C2 fix: one more seam clamp near the open front, on the bottom inner wall, so the
    # deep (148 mm) front edges of the two halves are pulled together, not left free.
    body = body.union(cq.Solid.makeBox(
        SEAM_BLOCK_L, POST_DEPTH, SEAM_BLOCK_H,
        cq.Vector(-SEAM_BLOCK_L / 2, FRONT_SEAM_Y - POST_DEPTH / 2, WALL)))
    body = body.union(_foot(SEAM_BLOCK_L, POST_DEPTH, (0, FRONT_SEAM_Y, WALL), (0, 0, 1)))
    fzc = WALL + SEAM_BLOCK_H / 2
    body = body.cut(_cyl(CLR_M3, SEAM_BLOCK_L / 2 + EPS,           # -X clearance
                         cq.Vector(-SEAM_BLOCK_L / 2 - EPS, FRONT_SEAM_Y, fzc), cq.Vector(1, 0, 0)))
    body = body.cut(_cyl(INSERT_M3, SEAM_BLOCK_L / 2 + EPS,        # +X insert
                         cq.Vector(0, FRONT_SEAM_Y, fzc), cq.Vector(1, 0, 0)))

    # Dowel posts straddling the split, top and bottom, on the rear inner wall.
    for z in (OUT_Z - BORDER, BORDER):
        body = body.union(cq.Solid.makeBox(
            POST_L, POST_DEPTH, POST_H,
            cq.Vector(-POST_L / 2, WALL, z - POST_H / 2)))
        body = body.union(_foot(POST_L, POST_H, (0, WALL, z), (0, 1, 0)))
        body = body.cut(_cyl(DOWEL_D + TOL, POST_L + 2 * EPS,
                             cq.Vector(-POST_L / 2 - EPS, WALL + POST_DEPTH / 2, z),
                             cq.Vector(1, 0, 0)))

    # 4 buttons as a 2x2 rectangle in the -X end wall, encoder above the top-right.
    xw = -OUT_W / 2 - EPS
    for by in BTN_COLS_Y:
        for bz in BTN_ROWS_Z:
            body = body.cut(_cyl(BTN_D + TOL, WALL + 2 * EPS,
                                 cq.Vector(xw, by, bz), cq.Vector(1, 0, 0)))
    body = body.cut(_cyl(ENC_D + TOL, WALL + 2 * EPS,
                         cq.Vector(xw, BTN_COLS_Y[1], ENC_Z), cq.Vector(1, 0, 0)))

    # Rear (-Y) wall: status LEDs, XT60 power inlet, honeycomb vents.
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
    # Honeycomb grille centred on the +X end wall (the side slit vents are gone).
    ecy, ecz, ew, eh = END_GRILLE
    body = body.cut(_hex_grille(ecy, ecz, ew, eh, HEX_PITCH, HEX_WALL,
                                OUT_W / 2 - WALL - EPS, OUT_W / 2 + EPS, axis="x"))
    # SMA bulkhead hole for the SDR antenna, same end wall (SDR side).
    body = body.cut(_cyl(ANT_HOLE_D, WALL + 2 * EPS,
                         cq.Vector(OUT_W / 2 - WALL - EPS, ANT_POS[0], ANT_POS[1]),
                         cq.Vector(1, 0, 0)))

    # Camera: a downward-hanging box (+X, near the Pi), open at the top, set back so it
    # clears the front panel; looks forward + slightly down. The radar moved to the LED
    # tower and the microphone to the Pi 5 (USB), so the bottom face has no other openings.
    body = _camera_pod(body)
    # Speaker grille (BF 45, down-firing), on the bottom between the camera box and -X end.
    body = _speaker_grille(body)

    # BME280 ambient opening + drop-in cradle on the bottom, so it reads OUTSIDE air.
    bx, by = BME_POS
    for gx in (-4.0, 0.0, 4.0):
        for gy in (-4.0, 0.0, 4.0):
            body = body.cut(_cyl(2.0, WALL + 2 * EPS,
                                 cq.Vector(bx + gx, by + gy, -EPS), cq.Vector(0, 0, 1)))
    bp, bw = BME_POCKET, BME_POCKET_WALL
    bcr = cq.Solid.makeBox(
        bp + 2 * bw, bp + 2 * bw, BME_POCKET_H,
        cq.Vector(bx - bp / 2 - bw, by - bp / 2 - bw, WALL))
    bcr = bcr.cut(cq.Solid.makeBox(
        bp, bp, BME_POCKET_H + 2 * EPS, cq.Vector(bx - bp / 2, by - bp / 2, WALL - EPS)))
    bcr = bcr.cut(cq.Solid.makeBox(       # open the cable side (-Y, toward the carrier)
        bp, bw + 2 * EPS, BME_POCKET_H,
        cq.Vector(bx - bp / 2, by - bp / 2 - bw - EPS, WALL)))
    body = body.union(bcr)

    # Condensation drain in the bottom wall (clear spot).
    ddx, ddy = BOTTOM_DRAIN_POS
    body = body.cut(_cyl(DRAIN_D, WALL + 2 * EPS, cq.Vector(ddx, ddy, -EPS), cq.Vector(0, 0, 1)))

    # Internal stiffening ribs on the inner bottom wall (against long-panel warp), running
    # front-to-back at a few X, clear of the tower/camera/BME/drain and below the panel.
    for rx in RIB_X:
        body = body.union(cq.Solid.makeBox(
            RIB_W, 108.0, RIB_H, cq.Vector(rx - RIB_W / 2, 12.0, WALL)))

    # Downward LED indicator tower: a tapered box (wide at the top, 40x40 tip, LED_TAPER
    # draft) hollow and open to the cavity, with one LED hole per slanted side (glue LEDs
    # from inside; they spray out and downward in four directions).
    lbx, lby = LED_BOX_POS
    top = LED_BOX + 2 * LED_BOX_H * math.tan(math.radians(LED_TAPER))
    tower = (cq.Workplane("XY").rect(top, top)
             .workplane(offset=-LED_BOX_H).rect(LED_BOX, LED_BOX)
             .loft(combine=False)).translate((lbx, lby, 0))
    body = body.union(tower)
    itop, ibot = top - 2 * LED_BOX_WALL, LED_BOX - 2 * LED_BOX_WALL
    cav = (cq.Workplane("XY").workplane(offset=WALL + EPS).rect(itop, itop)
           .workplane(offset=-(LED_BOX_H - LED_BOX_WALL + WALL + EPS)).rect(ibot, ibot)
           .loft(combine=False)).translate((lbx, lby, 0))
    body = body.cut(cav)
    off = (top + LED_BOX) / 4.0                     # face-centre horizontal offset
    n_out, n_down = math.cos(math.radians(LED_TAPER)), math.sin(math.radians(LED_TAPER))
    # 3 LED holes on the side/rear faces...
    for dx, dy in ((1, 0), (-1, 0), (0, -1)):
        normal = cq.Vector(dx * n_out, dy * n_out, -n_down)
        centre = cq.Vector(lbx + dx * off, lby + dy * off, -LED_BOX_H / 2.0)
        body = body.cut(cq.Solid.makeCylinder(
            LED_HOLE_D / 2, 8.0, centre - normal.multiply(4.0), normal))
    # ...and a radar slot in the front (+Y) face for the LD2410B, facing forward. The
    # slot (RADAR_WIN_L x RADAR_WIN_W, horizontal) exposes all three antenna patches of
    # the 35x7 board, which glues over it from inside and seals the tower.
    rnorm = cq.Vector(0, n_out, -n_down)
    rcentre = cq.Vector(lbx, lby + off, -LED_BOX_H / 2.0)
    rpl = cq.Plane(origin=rcentre - rnorm.multiply(4.0), xDir=(1, 0, 0), normal=rnorm)
    body = body.cut(cq.Workplane(rpl).slot2D(RADAR_WIN_L, RADAR_WIN_W).extrude(8.0))
    # Drain in the tower floor (lowest point): condensation + powder escape.
    body = body.cut(_cyl(DRAIN_D, WALL + 2 * EPS,
                         cq.Vector(lbx, lby, -LED_BOX_H - EPS), cq.Vector(0, 0, 1)))

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

    # Ceiling service/vent opening: a big rounded rectangle through the top wall,
    # notched around the WLED cradle so that pocket keeps its ceiling wall (a tongue
    # of material reaches in from the front border to hold it). Cut pre-mirror, so it
    # stays aligned with the cradle when the whole body is mirrored.
    lid_len_y = OUT_Y - 2 * LID_MARGIN
    lid_cy = LID_MARGIN + lid_len_y / 2
    lid = (cq.Workplane("XY")
           .box(OUT_W - 2 * LID_MARGIN, lid_len_y, WALL + 2 * EPS)
           .translate((0, lid_cy, OUT_Z - WALL / 2))
           .edges("|Z").fillet(LID_CORNER_R))
    knx = pw + 2 * WLED_WALL + 2 * LID_NOTCH_M
    kny1 = wcy + pl / 2 + WLED_WALL + LID_NOTCH_M   # tongue reaches in from the rear
    lid = lid.cut(cq.Solid.makeBox(
        knx, kny1 + EPS, WALL + 4 * EPS,
        cq.Vector(wcx - knx / 2, -EPS, OUT_Z - WALL - 2 * EPS)))
    body = body.cut(lid.val())

    # Reinforce that tongue: thicken the ceiling wall over the notch downward by
    # LID_TONGUE_RIB so it does not flex or snap at its root, keeping the cradle pocket
    # clear so the WLED board still drops in. There is head-room here inside the box.
    rib = cq.Solid.makeBox(                        # overlap the standing tongue wall so
        knx, kny1 + EPS, WALL + LID_TONGUE_RIB,    # the union fuses cleanly (no slivers)
        cq.Vector(wcx - knx / 2, -EPS, OUT_Z - WALL - LID_TONGUE_RIB))
    rib = rib.cut(cq.Solid.makeBox(                # keep the cradle pocket open below the wall
        pw, pl, LID_TONGUE_RIB + 2 * EPS,
        cq.Vector(wcx - pw / 2, wcy - pl / 2, OUT_Z - WALL - LID_TONGUE_RIB - EPS)))
    body = body.union(rib)

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
            # profile in X-Z: flat pad on top, then a CONCAVE arc sweeping back into the
            # wall (organic "cast" blend instead of a tacked-on ramp).
            top_out = (wall + outer, OUT_Z)
            pad_bot = (wall + outer, OUT_Z - EAR_T)
            root = (wall, OUT_Z - EAR_T - RAMP_H)
            arc_mid = (wall + outer * 0.28, OUT_Z - EAR_T - RAMP_H * 0.62)
            ear = (cq.Workplane("XZ")
                   .moveTo(wall, OUT_Z).lineTo(*top_out).lineTo(*pad_bot)
                   .threePointArc(arc_mid, root).close()
                   .extrude(-EAR_W).translate((0, yc - EAR_W / 2, 0)))
            # soften the ear's outer vertical edges (keep the top flush and the inner
            # wall edges sharp so they merge cleanly on union).
            osel = ">X" if sx > 0 else "<X"
            try:
                ear = ear.edges("|Z").edges(osel).fillet(EAR_EDGE_R)
            except Exception:
                pass
            body = body.union(ear)
            # C1 fix: a full through-hole (top through the ramp to the underside) plus a
            # counterbore giving the M5 head a flat, level seat. The old hole was only in
            # the 6 mm pad and dead-ended in the solid ramp below — a screw could not pass.
            hx = wall + outer / 2
            body = body.cut(_cyl(EAR_HOLE, EAR_T + RAMP_H + 2 * EPS,
                                 cq.Vector(hx, yc, OUT_Z - EAR_T - RAMP_H - EPS),
                                 cq.Vector(0, 0, 1)))
            body = body.cut(_cyl(EAR_CB_D, RAMP_H + EPS,
                                 cq.Vector(hx, yc, OUT_Z - EAR_T - RAMP_H - EPS),
                                 cq.Vector(0, 0, 1)))

    # Optional full left/right mirror, applied to the finished geometry so every
    # feature, board boss, sensor and vent flips at once. The raised text is added
    # AFTERWARDS (at mirrored X) so it stays readable instead of coming out backwards.
    if MIRROR:
        body = cq.Workplane(obj=body.val().mirror("YZ"))
    sx = -1.0 if MIRROR else 1.0

    # Bottom (-Z) brand plate: big Balkon Borg with small HagiOne below it.
    bbx, bby = BB_POS
    body = _bottom_text(body, TEXT_BOTTOM, sx * bbx, bby, BOTTOM_SIZE, TEXT_DEPTH)
    hgx, hgy = HG_POS
    body = _bottom_text(body, "HagiOne", sx * hgx, hgy, BOTTOM_HG_SIZE, TEXT_DEPTH)
    # Rear wordmarks, each centred in its half (see REAR_TEXTS), clear of the seam.
    for s, cx, cz, size in REAR_TEXTS:
        body = _rear_text(body, s, sx * cx, cz, size, TEXT_DEPTH)

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

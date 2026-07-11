# Decision log — Balkon-Borg

Chronological log of design decisions. Append newest entries at the top. Purpose: to
record *why* the build is the way it is, so settled questions are not reopened. Do not
log what is already in the code/YAML.

**Entry format:**

```
## YYYY-MM-DD — short title

**Context:** what it was about, the starting situation.
**Decision:** what was fixed.
**Rationale:** why this way, not another.
**Rejected:** which alternative(s) and for what reason. (optional)
**Consequences:** what this means for the rest of the build. (optional)
```

---

## 2026-07-11 — Depth +20 mm for WLED-to-LED clearance

**Context:** a packaging check (plan + rear sections drawn from the CAD dimensions)
showed everything fits with big margins except the WLED controller: mounted on the top
wall it hangs 44 mm forward (to y=77) and came within **5 mm of the warm LED panel back**
(y=82). The rear-mounted boards (Pi+cooler, carrier+ESP) were fine at 51-55 mm.

**Decision:** deepen the enclosure `DEPTH` 95 → **115 mm** (outer Y 98 → 118). The LED
panel moves forward with the front frame while the top-wall WLED stays put, so the gap
grows 1:1: **WLED-to-LED now 25 mm** (target ≥15-20). Rear boards now 71-75 mm clear.

**Rationale:** the user preferred adding depth ("stört ja nicht") over relocating the
WLED. +20 mm gives a comfortable warm-clearance and a round number; the unit hangs under
the balcony so extra depth is free.

**Still open (minor):** the WLED footprint sits over the carrier's top-right corner in
X-Z with only 6 mm of depth between them (no collision). Nudging `WLED_CENTER` into the
middle bay would clear it fully if wanted. Component heights (Pi cooler, ESP stack, WLED
body) are estimates pending real measurement.

---

## 2026-07-11 — Rear wall as keep-out zones + centred grille/wordmark layout

**Context:** the single grille was small and off to one side, and the rear wordmark was
small and looked oddly offset. Wanted a systematic layout: mark where the boards sit,
derive the free areas, then fill them with grille (with margin) and the centred
HagiOne / Balkon Borg wordmarks.

**Two realisations that drive the layout:**
- **Raised text may sit anywhere** on the rear (it is on the outside of the wall); only
  grille openings, which cut through, must dodge the board keep-outs.
- There is a **split seam at X=0**. Nothing may cross it (it would be cut between the
  two printed halves). This was the real cause of the "oddly offset" wordmark: HagiOne
  sat centred on x=0, i.e. straight on the seam.

**Decision — computed layout, everything centred in its own zone, nothing on the seam:**
- Keep-outs (for holes): carrier board (left), Pi board (centre-right), status LEDs and
  XT60 (right), divider ribs, seam.
- **Four honeycomb panels** (`REAR_GRILLES`) in the board-free zones: far left of the
  carrier and the middle bay right of the seam (both tall), plus the wide-flat strips
  above and below the Pi. All verified clear of every board, boss, rib and the seam.
- **Two wordmarks** (`REAR_TEXTS`), **bold**, bigger (HagiOne 22, Balkon Borg 16), each
  centred in one half (x=-115 / x=+115, z=55), clear of the seam.
- The offset bug is fixed by placing text on a **ProjectedOrigin workplane** at the exact
  (cx, cz) (`_rear_text`) instead of trusting the face bounding-box centre.

Supersedes the earlier single wide-flat grille from today.

---

## 2026-07-11 — Rear hex honeycomb grille (replaces the diagonal louvres)

**Context:** the diagonal rear louvres were too small and too boring. Wanted a really
cool vent, feasible in the material, at ~1/6-1/7 of the rear-wall area.

**Decision:** a **hex honeycomb grille** on the rear wall (`_hex_grille` in
`cad/balkon_borg.py`), a field of pointy-top hexagons. `HEX_PITCH=12`, `HEX_WALL=2.2`
→ 9.8 mm openings, webs 2.2 mm (> the 1 mm SLS minimum). Cells that would poke past the
field are dropped, giving a clean rectangular field with a naturally stepped honeycomb
border. HagiOne stays in the band above it.

**Field wide and flat, clear of the board mounts (revised after review):** the grille
must not sit over any PCB-holding structure. Placed entirely in the **board-free middle
bay** — between the carrier board (x ≤ -30), the Pi board (x ≥ 52) and clear of the
divider ribs (x = -25/48). Field **66×40 mm at (11, 53)** (x[-22,44] z[33,73]), aspect
~1.65, ~5 % of the rear face. Verified: nothing behind it (no boss, board or rib), below
the HagiOne band. Trade-off: the clear middle bay is only ~70 mm wide, so a
construction-free grille is smaller than the earlier 1/6-1/7 target; kept wide-and-flat
per the request. Widening further would mean relocating a board or a divider.

**Rationale:** honeycomb is the classic "cool enclosure vent", reads technical/premium
and pairs with the cast SLS look; SLS prints it with no supports. Voronoi was the
alternative (more organic) but nondeterministic and busier; honeycomb is deterministic
and cleaner. Generous open area also improves airflow over the old 2 mm slits.

**Consequence:** the straight/diagonal rear intake slits are gone; the end-wall exhaust
slits stay. Grid is fully parametric (centre/size/pitch/web).

---

## 2026-07-11 — Hollowing fix, open front, diagonal louvres, docs to English

**Context:** the STL came out as a near-solid block with a closed front. Cause found:
filleting the vertical edges (`.edges("|Z")`) *before* `.faces(">Y").shell(-WALL)`
makes OCC's shell return the solid instead of hollowing it (verified: box+shell = 473
cm³ hollow, with a `|Z` fillet before the shell = 4955 cm³ solid; a `|Y`-only fillet
stays hollow). Filleting *after* the shell fails too (`StdFail_NotDone` on the inner
edges).

**Decision:** round the outer edges on the solid box, then hollow with an **inner-box
`cut`** (open front) instead of `shell`. Body back to ~645 cm³ hollow, front + cavity
open, rounded corners kept. Rule for the future: **do not `shell` a filleted body**;
fillet the solid and cut the cavity.

**Bezel dropped (final):** the front is **open**; diffuser + LED panel are glued in at
the end (no separate bezel part). Supersedes the bezel mentions in the earlier
2026-07-11 review entry. The two printed parts are just `balkon-borg-left/right`.

**Diagonal rear louvres:** the straight rear intake slits become a group of **diagonal**
louvres in the clear zone between the boards (styling cue, same insect-safe 2 mm gap).

**HagiOne on the rear wall:** raised HagiOne wordmark added to the rear wall above the
louvres, in addition to the +X end.

**`make preview`:** now builds everything and prints the `feh`/`f3d` view commands
instead of launching a viewer (no GUI from make in this environment).

**Docs to English:** per the project language rule, all repo docs translated to English
(README, CLAUDE.md, this log, the cad/pcb/firmware READMEs, board-spec, build-notes,
power-distribution, enclosure-sintering). Stale ASA references pulled to the current SLS
state; provider recommendation flipped to Germany first.

---

## 2026-07-11 — Manufacturing: SLS/PA12 black (instead of FDM/ASA)

**Decision:** the enclosure is made by **SLS** in **PA12 nylon, black**, no longer
FDM/ASA. Reason: **more professional look** (matte, even surface without layer
lines/seam/supports), no supports, isotropically strong.

**Weather clarification defuses the PA12 downsides:** location fully protected, **no
sun** (UV moot), **no rain** (water moot), only humidity (PA12 takes up ~0.5-1 % → for
an enclosure irrelevant). No coating needed.

**Metal rejected:** a Faraday cage blocks WiFi + radar; metal printing at 4.5 l would
also be thousands of euros/kilos heavy. (Optionally the front as an aluminium bezel,
body plastic.)

**Design adapted to SLS:** `TOL` 0.2 → **0.4 mm** (SLS fit), front insert holes made
through-going (powder escape instead of a blind cavity), split stays (build volume
~230 mm). The ASA-specific rule (V-0 separation) in CLAUDE.md generalised to "printed
enclosure"; README §6 "ASA/PLA" is thereby outdated (material now PA12).

**Providers:** JLC3DP (PayPal, cheapest, China shipping) vs. Craftcloud/ZELTA3D/
PRINCORE (EU/DE, faster shipping). Details + procedure in
[[docs/enclosure-sintering.md]] (`docs/enclosure-sintering.md`).

---

## 2026-07-11 — Review fixes: robust enclosure, firmware, distribution

Worked off autonomously after the enclosure and component review:

**Enclosure (`cad/balkon_borg.py`):**
- **Seam screwing:** clamp blocks at X=0 (clearance -X / M3 insert +X) + dowels. The
  bezel additionally clamps the front seam. (Critical bug fixed: the halves were only
  aligned before, not clamped.)
- **Screwable front:** a separate **bezel** (`balkon-borg-bezel-left/right`) clamps the
  diffuser (no gluing), front access for service. RECESS=0, M2.5 inserts in the front
  border.
- **New ventilation:** 2 mm slits in the clear rear-wall middle zone (previously behind
  the boards), exhaust high on the end walls, insect-fine.
- **Boss holes at insert size** (M2.5=3.4 / M3=4.0) instead of self-tapping.
- **Mounts + dividers:** WLED (top wall), radar/mic/BME (bottom), divider ribs (carrier
  | middle | Pi). Pi+SDR as a larger keep-out towards +X.
- **BME280 bottom opening** (grid) for outside air.
All features verified numerically, body 622 cm³, builds without error.

**Firmware (`firmware/esphome/balkon-borg.yaml`):** buttons/encoder/radar/BME →
**light control directly over WLED MQTT** (toggle, presets, brightness, presence
automation, status LEDs). YAML structurally validated.

**System docs:** `docs/power-distribution.md` (5 V star with **10 A LED / 5 A Pi branch
fuses**), `docs/build-notes.md` (Pi5 PD/`usb_max_current_enable`, ESP flash before
install, WiFi antenna placement, print orientation, hardware checklist).

**User decisions:** ADS-B not used (no sky antenna); heat-set inserts instead of
self-tapping; screwable front wanted.

**Placeholders to verify:** WLED/BME280 module dimensions, Athom hole pattern.

---

## 2026-07-10 — Wide power traces + ESP row spacing confirmed

**Power traces:** the "Power" net class (in `place-board.py` via
`NET_SETTINGS.SetNetclassPatternAssignment`) sets **+5V/+5V_IN/GND to 1.0 mm** (holds
~3 A, 1oz), signals stay 0.2 mm. Reason (a friend's tip): a 0.25 mm trace holds only
~0.7 A and would burn out before the 2 A fuse F1 → F1 would be pointless. Lands
correctly in the DSN (`(class Power ... (width 1000))`), Freerouting routes
accordingly. Verified: +5V/GND = 1.0 mm, DRC 0/0.

**ESP row spacing confirmed: 25.4 mm (1 inch)**, the official Espressif dimension for
the DevKitC-V4 (several sources). Was already the placeholder value → no change.
(Clones like AZ-Delivery: 25.0 mm, the difference is within socket tolerance.) So
`ESP_ROW=25.4` is final, no longer an open point.

---

## 2026-07-10 — Board finalised + coupled to enclosure, HagiOne on it

**Board final:** 150×92 mm, freshly placed compact, **4 M3 corner holes** (pattern
136×78), **"HagiOne" as F.Silkscreen** top centre. Re-autorouted, **DRC 0/0**, Aisler
zip regenerated. The whole cycle ran **headless by script** (`place-board.py` → DSN via
`pcbnew.ExportSpecctraDSN` → Freerouting → `apply-ses.py` via
`pcbnew.ImportSpecctraSES`); KiCad GUI only for viewing.

**Enclosure↔board coupling (shared truth):**
- `cad/balkon_borg.py`: `CARR_BOARD_W/H=150/92`, `CARR_HOLE_DX/DZ=136/78`,
  `CARR_CENTER=(-105,55)`. Bosses at (-173,16),(-173,94),(-37,16),(-37,94) = exactly the
  4 board holes. These values MUST match `pcb/place-board.py`.
- Board sits on the rear-wall inside, left (x -180..-30), 96 mm from the Pi (x 66..124).
  **Status LEDs moved right** (x 150-210) so they are not behind the board.

**Only open:** measure the ESP header row spacing (ESP_ROW, in place-board.py AND as the
socket footprint) on the real DevKit; the outline is now real (150×92), no longer a
placeholder.

---

## 2026-07-10 — Board placed + autorouted (unrouted 0)

**Placement:** `pcb/place-board.py` (KiCad pcbnew module, system Python) arranges the 33
footprints tidily (2 vertical ESP columns centred, resistors flanking, connectors at the
edges, transistors above the buttons) and draws a placeholder outline 160×110. ESP
headers are vertical 1x19 columns, spacing ESP_ROW=25.4 mm (placeholder, check on the
real DevKit).

**Routing:** Freerouting **1.9.0** (Java 21; 2.x needs Java 25) headless over the DSN
exported from KiCad, batch (`-de/-do -mp 30 -oit 1`) on DISPLAY=:0. Fully routed in ~1 s,
optimisation ~50 % shorter, `.ses` imported back into KiCad → **unrouted 0**. The jar
lives in the scratchpad (not in the project).

**DRC clean (0/0).** Fabrication data generated via `scripts/gen-outputs.py` →
`pcb/output/balkon-borg-carrier-aisler.zip` (Gerber + drill file). BOM empty (parts in
the board, no schematic) — irrelevant for the bare board.

**Set final before really ordering:** measure the ESP header row spacing on the real
DevKit (else the module will not seat), take the outline from the enclosure carrier bay
(currently placeholder 160×110).

---

## 2026-07-10 — Board: netlist via SKiDL (instead of a GUI schematic)

**Context:** at the board step "KiCad" the choice was: a full GUI schematic in Eeschema
(much clicking, error-prone with the 38 ESP pins) vs. a netlist from code. The user chose
**code**.

**Implementation:** `pcb/gen-netlist.py` (SKiDL, tool KICAD9) describes the complete
circuit from `docs/board-spec.md` incl. the **correct ESP32-DevKitC-V4 pin assignment**
(official pinout, J2 left / J3 right). ESP as 2× `Conn_01x19` (socketed). Produces
`balkon-borg-carrier.net` (KiCad netlist), **0 errors**, 33 parts with footprints. End to
end verified (I2C_SDA→J3.6/GPIO21, RADAR_TX→J3.12/GPIO16, BTN_LEDK→Q.Collector,
+5V/+3V3/GND correct).

**Procedure:** import the netlist in the KiCad PCB editor (*File → Import → Netlist*),
then layout (outline, placement, routing) in the GUI. The user only does the layout, the
error-prone pin logic is in code. Circuit changes always in `gen-netlist.py`.

**Toolchain:** SKiDL 2.2.3 in the venv; needs `KICAD9_SYMBOL_DIR` /
`KICAD9_FOOTPRINT_DIR` on `/usr/share/kicad/{symbols,footprints}`.

---

## 2026-07-10 — XT60E-M real, finishing (gussets, panel nubs, tolerances)

**Power connector: Amass XT60E-M** (a really available panel mount, UL94-V0, 30/60 A,
well stocked). From the datasheet: body cut-out ~16×9 mm, 2× M3 (ø3.2) ~14 mm apart.
Entered in the model like this (fine-tune/glue on the real part). **Wiring confirmed:**
external PSU → short 5 V cable → XT60 in the rear wall → inside a dedicated 5 V cable to
the distribution → loads.

**Finishing in the model:**
- **Ear gussets:** triangular support ribs under all 4 ears (against breaking off at the
  root when screwing to the ceiling).
- **Panel positioning nubs:** 4 corner nubs on the frame back (the panel glues between
  them, does not slip).
- **Print tolerance:** global parameter TOL=0.2 mm on the fits (button holes 12.2,
  diffuser rebate, dowel-pin holes).

---

## 2026-07-10 — PSU external (final), power connector, sensor cut-outs

**PSU: external (final).** The PSU enclosure hangs next to the hub, ~5 m Schuko from the
PSU enclosure to the socket, only a **short 5 V hop** into the hub. Solves the fire-safety
topic (supersedes the parked "PSU inside" point); README §6 applies again.

**Confirmed and rejected:** the variant "PSU at the socket, 5 m 5 V cable to the hub" was
checked and **rejected** (5 V over 5 m at 10-15 A: >1 V drop, brownout; would need welding
cable). The long cable belongs on the 230 V side, not the 5 V side. User confirmed.

**Power connection: pluggable panel connector (XT60) in the rear wall.** The user wants to
plug/unplug. XT60: ~60 A, polarity-safe, robust, covers the ~10-15 A (panel + Pi). Cut-out
= rectangular hole + 2 screw holes (adjust to the real panel holder). Replaces the earlier
cable gland.

**Sensor cut-outs in the underside (-Z, looks down onto the terrace):**
- **Camera** (Module 3): 12 mm lens hole (generous) + 4 mounting bosses. Values from the
  official RPi drawing: board 25×23.862, holes ø2.2, pattern ~14.4×12.5 (asymmetric). The
  lens↔hole offset is not cleanly given in the drawing (RPi forum confirms), so the lens
  hole is large; check on the real part or glue the camera. CSI cable: **standard mini
  200 mm** (reach camera bottom ↔ Pi rear wall thus uncritical, CSI worry resolved).
- **Radar LD2410B: 2 mm membrane** (wall thinned to 2 mm inside, 26×26 mm).
- **Microphone**: 4 mm hole.
Right half of the underside (x>0), clearly beside the Balkon-Borg slogan (left) and the
seam.

**Open/placeholder:** camera hole pattern + standoff height, XT60 holder dimensions,
radar/camera mounting in detail.

---

## 2026-07-10 — Open: PSU inside? (fire safety, parked)

**Context:** the user wants the 230 V PSU INSIDE the enclosure and a 4 m Schuko cable to
the outside. That contradicts README §6 (230 V separated in a V-0/metal enclosure, printed
part low voltage only).

**Status: open, parked.** Recommendation if inside: PSU in its own sheet-metal/V-0
compartment in the enclosure (230 V only there, Schuko with strain relief, PE to chassis,
only 5 V out, ventilation). Alternatives: open in the ASA (advised against, fire risk) or
external near the socket (safest). Decision deferred by the user; no other work blocked by
it.

---

## 2026-07-10 — Front seat, more depth, buttons to the side

**Front seat (user answers):** opal acrylic diffuser **3 mm**, in the front rebate, **1 mm
recessed**; **8 mm** air gap LED→diffuser; **rebate + glue** (no bezel). Implemented as a
12 mm deep front frame (FRAME_D): light window 434×84, in front of it a diffuser rebate
444×94 (4 mm deep), the panel glues to the frame back.

**Depth 75 → 95 mm:** room for all boards (WLED controller, RTL-SDR, mic, wiring). The
rear-wall area 454×104 was never tight; the front seat eats 12 mm, hence deeper. User:
"deeper does not matter".

**Buttons from below to the -X end wall** (vertical row). Reason (user): the boards are in
the way at the back/inside; the end wall is openly accessible during split assembly, so
easier to mount and wire. Consequence: the -X slogan drops, HagiOne stays +X, Balkon Borg
stays on the bottom. (Side -X, mirrorable by parameter.)

---

## 2026-07-10 — Orientation reversed: light to the front (supersedes downlight)

**Context:** after some back and forth, finally fixed. The "downlight" chosen in the tool
was corrected by follow-up messages. **Supersedes the downlight entry of the same day.**

**Final orientation ("front to the terrace"):**
- **Front (+Y, vertical, to the terrace): LED panel, light forward.** The open face =
  light window (panel + diffuser). **Stays text-free.**
- **Underside (-Z, down): buttons + encoder** (reachable from below).
- **Rear (-Y, to the house): status/effect LEDs** (small single LEDs, no area light), plus
  cable gland and ventilation.
- **Top (+Z): ceiling**, ears protrude in ±Y, screws vertical.
- **End walls (±X): slogans** (HagiOne / Balkon Borg).

**Axes in the model:** X = width (panel columns, 460), Z = height (panel 80 + border,
110), Y = depth (front-rear, ~78). Front +Y open. Pi5 + carrier hang on the rear-wall
inside. Split X=0 stays.

**Rationale:** user decision. The light should illuminate the seating corner, not the
table from above; operation from below; the rear for status display.

**Open:** place large slogans / further faces only once the new geometry is visible (faces
have shifted). Keep the CSI camera proximity to the front in view (Pi ~75 mm away on the
rear wall).

---

## 2026-07-10 — Slogans on the end walls

**Decision:** raised text (1.2 mm), printed along:
- **+X end wall: "HagiOne"** (the user's codename).
- **-X end wall: "Balkon Borg"** (project name, = repo directory).
- Font size 12 mm, horizontal along Y, centred on the wall. Each text lies fully within one
  split half (no seam conflict).
- **Ventilation slits moved to the +Y long wall for this** (end walls free for text).

**Rationale:** codename + project name as a nameplate; raised wanted. The end walls were
free anyway (operation -Y, cables +Y).

**Open:** the slogan on the lower printed plate (wanted earlier) still open; comes when
building the front light-window frame, if still wanted. Choose the print orientation so the
raised text does not print as an overhang.

---

## 2026-07-10 — Thermal rule dropped, lower plate is printed

**Context:** the project description made the aluminium plate the mandatory heatsink of the
LED layer ("thermal in summer" as the top risk). The user deliberately drops this: the LED
runs mostly at night, the location is cool enough, ventilation through side slits suffices.

**Decision:**
- **No mandatory aluminium heatsink anymore.** Overrides README §6 thermal and §4
  ("aluminium plate = front + heatsink"). Risk "thermal in summer" downgraded.
- **The lower plate is printed** (ASA), with a **diffuser light window** over the LEDs
  (light must pass, ASA is opaque). Aluminium drops as the load-bearing front plate.
- **Additional ventilation slits in the side walls.**
- Thus the lower printed face also carries the raised slogan.

**Rationale:** user decision, the usage profile (night, cool) carries the risk. Simplifies
the build (no aluminium purchase/contacting) and makes the slogan idea on the underside
printable in the first place.

**Consequence:** LED panel + diffuser sit in the light window of the printed lower plate.
If it does get too warm, an aluminium retrofit behind the LEDs is possible any time.

---

## 2026-07-10 — Ceiling mount: orientation, ears, side operation

**Context:** the enclosure is screwed to the ceiling (balcony underside), the panel points
down onto the table. The top is the ceiling side (inaccessible).

**Decisions (implemented in the CadQuery model):**
- **Orientation:** +Z = top (ceiling, closed top wall), -Z = bottom (open front,
  aluminium plate/panel/diffuser shines down). X = width, Y = depth.
- **Operation on the side wall**, not on top and not in the glowing front: 4 buttons
  (12 mm) + encoder (7 mm) as holes in the **-Y wall** (to the terrace). As a cluster in
  **one half** (x = 35..195), so no hole lands on the X=0 seam.
- **Ceiling fixing via side "nubs":** 4 tabs at the top corners, protruding in ±Y,
  vertical through-hole (~M5). Screw from below through the nub up into the ceiling anchor.
  The tab top flush with the enclosure top (rests against the ceiling).
- **Cable gland in the +Y side wall** (M12), no longer in the bottom.
- **Ventilation** as slits in the end walls near the open (lower) front, so heat/condensate
  can escape downward.
- **Pi5 + carrier** hang on bosses from the top wall; split X=0, dowel-pin posts.

**Rationale:** the ceiling position flips top/bottom; operation and cables have to go to
the side, because the ceiling is on top and the light field on the bottom. Nubs are the
simplest tool-friendly ceiling fixing (screwable from below).

**Open / parametric:** exact side/position choice (buttons -Y, cables +Y as default), ear
dimensions and ceiling screw size, vent arrangement. All parameters in
`cad/balkon_borg.py`. Camera/radar/mic cut-outs and the aluminium front plate as its own
part follow.

---

## 2026-07-10 — Enclosure from datasheet dimensions, not from measurement

**Context:** I had classified the CadQuery enclosure as "blocked until parts are measured".
The user rightly disagrees: the dimensions of the standard parts are online as drawings,
and his approach is deliberately generous ("bigger if in doubt, it just hangs there").

**Decision:** build the enclosure **now** from datasheet dimensions + generous clearances,
parametrically, no physical measurement needed. Tolerance via slack rather than precision.
Enclosure work is thus no longer blocked by parts arriving.

**The only real spatial constraint:** the short Pi 5 CSI cable → camera near the Pi.
Solution: Pi chamber behind the camera opening or a longer CSI FPC (200-300 mm). Not
covered by "build bigger", to be solved separately.

**Consequence:** order adjusted: the CadQuery enclosure can start in parallel/before the
schematic. The board outline is carried as a generously reserved bay in the enclosure, so
board layout and enclosure stay decoupled.

---

## 2026-07-10 — Concrete parts: ESP32 board, buttons, BME280 pull-ups

**Context:** the user delegates the part choice ("take what is technically suitable and
available, what everyone uses") and asks for a guide on the I²C pull-ups.

**Decisions:**
- **ESP32: Espressif ESP32-DevKitC-V4 (WROOM-32E), 38-pin, official.** Reason: quality over
  price, documented mechanics (row spacing given), widely available. Socketed on 2×
  `PinSocket_1x19_P2.54mm`. **KiCad has no DevKitC footprint** → header footprints, spacing
  from the Espressif drawing.
- **Buttons: 12 mm metal, momentary, illuminated, 5 V ring LED, 1NO (IP65)**, the common
  standard type. Consequence: a 5 V LED cannot be driven directly from a 3.3 V GPIO → **one
  NPN per button (BC337-40/2N3904, TO-92)** as a low-side switch, GPIO through 1 kΩ to the
  base. The button connector is thus **4-pin** (SW, GND, 5V, LEDK). The 4× 330 Ω LED
  resistors drop (the LED brings its own).
- **BME280 pull-ups: 2× 4.7 kΩ as DNP** provided. Almost all breakouts have pull-ups on
  board → the spots stay empty, populate only in the exceptional case. Buy a **genuine
  Bosch BME280**, avoid BMP280 fakes (no humidity).

**Rationale:** all three choices aim at "common, available, robust, low-solder for a
non-hardware builder". The NPN driver is the price for common illuminated buttons having
5 V LEDs; the alternative (2 V LED directly on the GPIO) would be part-dependent and
fragile.

**Rejected:** 30-pin clone board (lower QC, variable row spacing) in favour of the official
DevKitC-V4. Direct GPIO LED drive in favour of the NPN driver.

**Open:** enter the row-spacing dimension from the Espressif drawing; when ordering ensure
the 5 V button variant; board outline further from the enclosure.

---

## 2026-07-10 — Button size final: 12 mm

**Context:** briefly switched to 16 mm (because of big fingers), but immediately taken back
to **12 mm** by the user. So it stays at 12 mm.

**Decision:** illuminated buttons **12 mm**. Ergonomics is instead handled via **generous
spacing** between the buttons (see the ergonomics entry), not via larger buttons. Board
schematic unchanged; front hole 12 mm, LED model in board-spec point 2.

---

## 2026-07-10 — Ergonomics: size up generously

**Context:** the user has big fingers and is, by his own account, rather clumsy. Board and
enclosure may be "a little bigger".

**Decision:** design generously throughout. Controls, connectors and fixings well apart;
the board may grow beyond the minimum; the enclosure roomy. No cramped layouts, no fiddly
assembly.

**Consequence / open tension:** the user found the stainless buttons "coarse" and chose
12 mm, but big fingers argue rather for bigger buttons **or** clearly generous spacing
between the 12 mm buttons. Watch for this in the front layout; re-check button size against
usability if needed (16 mm stays an option). Also saved as a persistent user note
([[user-prefers-roomy-builds]]).

---

## 2026-07-10 — EDA tool to KiCad, illuminated buttons, enclosure requirements

**Context:** the user left the tool choice open again ("if other software is installable on
Debian, gladly") and is not a hardware/firmware person. Plus new wishes: finer,
preferably self-lit buttons; various things screwable inside the enclosure (Pi5, camera);
note that the Pi 5 CSI camera cable is very short.

**Decisions:**
- **EDA tool: KiCad (GUI)** instead of atopile. **Supersedes the atopile decision** of the
  same day. Reason: via apt on Debian, huge THT library, best Aisler integration (direct
  push/native import), no library tinkering. Fits the non-hardware profile. Python stays
  only for fabrication output/DRC/BOM, not for the first draft. The code ethos still holds
  for the CadQuery enclosure, not the PCB.
- **Buttons: illuminated, 12 mm metal**, momentary, with LED, screwable into the front
  (replacement for the stainless buttons felt "too coarse"). Count "a few", 4 for now
  (adjustable).
  - **Board consequence:** per button a **3-pin JST-XH** (SW signal, LED drive, common
    GND) instead of the earlier collective connector. LED **GPIO-controlled** through a THT
    resistor → can show state (scene/automation). The DevKitC GPIO budget suffices (count:
    UART 2 + radar OUT 1 + I²C 2 + encoder 3 + 4 button inputs + 4 LED outputs = 15 usable
    GPIOs, fits).
  - **Front consequence:** 12 mm holes with a panel nut instead of large stainless
    cut-outs.

**Captured enclosure requirements (CadQuery track, to detail later):**
- **Pi5 in its own chamber** with screw bosses (the Pi5 M2.5 hole grid), near the camera
  because of the short CSI; separated from the cool sensor front panel, with
  ventilation/Active Cooler room.
- **Camera** as its own module (not on the carrier board, own CSI interface) in its own
  seat behind a front cut-out. Short CSI → Pi chamber directly behind or procure a longer
  CSI FPC (settle with the enclosure).
- **Carrier board** gets its own screw holes to enclosure bosses (hole pattern from the
  enclosure, still open).
- Still holds: 230 V PSU in its own V-0 chamber, separated from the printed part.

**Rejected:** atopile (young, SMD-heavy, THT library effort) and SKiDL in favour of the
KiCad GUI. Unlit and 16 mm buttons in favour of 12 mm illuminated.

**Consequence:** `pcb/` becomes a KiCad project. Next step: install KiCad on Debian,
project skeleton, schematic per current spec.

---

## 2026-07-10 — Carrier board: tool, ESP32, power, connectors

**Context:** in addition to the enclosure, a **carrier board (carrier/backplane) for
sensors and signals only** should come about (ESP32 domain: LD2410B radar, BME280, 4
buttons, encoder), fabricated at **Aisler** (EU). No system backplane; the light side
(Athom WLED + SK6812 panel, own 5 V/data cable) and the Pi peripherals (RTL-SDR, USB mic,
camera) stay separate.

**Decisions:**
- **Tool: atopile** (code-first EDA, own language), export to KiCad → Aisler. Chosen
  despite the note that the official KiCad Python API is poor for the first draft (Eeschema
  has no stable Python API). **>> SUPERSEDED the same day, see the entry "EDA tool to
  KiCad, illuminated buttons". Now KiCad GUI.**
- **ESP32: ESP32-DevKitC (38-pin), pluggable** on headers, solder-free swappable and
  regularly orderable. The user is explicitly not a hardware/firmware tinkerer, hence
  pluggable instead of a soldered bare module.
- **Power: 5 V in, 3.3 V from the ESP module.** The board brings only fused 5 V to the
  DevKit; its onboard regulator supplies ESP and sensors with 3.3 V. No own regulator on
  board (minimal, robust). Keep the limit in view: does the DevKit LDO suffice for BME280 +
  radar? The LD2410B runs on 5 V, does not draw 3.3 V.
- **Connectors: JST-XH (2.5 mm) throughout** for all branches, polarity-safe, crimped. One
  uniform pitch, cheap, low-solder.

**Rationale:** atopile fits the project's "everything as code" ethos best (cf. the CadQuery
enclosure) and encapsulates building blocks as reusable modules, which relieves the
non-hardware user. Pluggable DevKit + JST + 5 V pass-through are the lowest-solder, most
robust path and cover the "cheap, replaceable front panel" role.

**Rejected / weighed:**
- *KiCad Python API (pcbnew/kipy)* and *SKiDL* as the primary path rejected in favour of
  atopile; **but they stay a fallback** if atopile hits maturity/library limits. The switch
  costs layout, not the design decisions.
- *Own 3V3 regulator on board* and *pure signal pass-through* rejected.
- *Qwiic/STEMMA* and *screw terminals* rejected in favour of uniform JST-XH.

**Population & protection (confirmed):**
- **Hand-soldered, THT only.** The board exclusively with through-hole parts: JST-XH
  headers, headers for the DevKit, THT resistors. No Aisler assembly. Consequence: atopile
  may need **THT footprints/custom parts** (the library is SMD-heavy), which I carry.
- **Protection minimal: series resistors only** (THT) on the radar UART, encoder and button
  lines. **No TVS/ESD diodes** (would be bulky in THT). I²C needs pull-ups: either the
  BME280 breakout supplies them, else 4.7 kΩ THT on board (still to clarify, depends on the
  chosen breakout).

**Open / assumptions (still to confirm):**
- **Board outline + mounting holes** coupled to the CadQuery enclosure (open point README
  §8.3, board not yet measured) → parametric placeholders for now.
- **Layers:** Aisler default 2 layers assumed (sufficient for a sensor carrier).
- **GPIO pinmap** ESP32↔sensors/buttons still to fix (to coordinate with the ESPHome side,
  README §8.1).

**Consequences:** a new domain directory `pcb/` (atopile project) once first content
appears. Extend the CLAUDE.md domain table accordingly.

---

## 2026-07-10 — Project and memory structure created

**Context:** project start Balkon-Borg. A hardware-plus-software hobby project with several
domains (CAD, ESP32 firmware, WLED, backend services). A wish for a persistent memory layer
so decisions survive over time and are available at every Claude start.

**Decision:** three core files in the project root:
- `CLAUDE.md` — working context, loaded automatically at every Claude start; points
  explicitly to this log and to `README.md`.
- `README.md` — full project overview (the delivered description).
- `log/decisions.md` — this decision log.

**Rationale:** `CLAUDE.md` is the standard mechanism Claude Code reads at start. By pointing
to `log/decisions.md`, the log reliably becomes part of the start context. Separating
reference (README, static) and history (log, growing) keeps both clean.

**Consequences:** future non-trivial decisions are appended here as dated entries. Domain
artefacts go into the directories fixed in `CLAUDE.md` (`cad/`, `firmware/esphome/`,
`wled/`, `deploy/quadlets/`, `docs/`), once first real content appears.

---

## Pre-decided from the project description (starting situation, as of 2026-07-10)

Already fixed with the description, documented here as the starting situation (not to be
discussed again unless a new reason appears):

- **Compute-node roles:** the edge Pi 5 does recording and local inference; the ESP32 is the
  replaceable sensor/control front panel; the NAS-Pi 5 is broker/storage.
- **Object recognition on the Pi 5 CPU**, no AI HAT/Hailo (PCIe stays free for a later
  retrofit or NVMe). Consequence: FPS/stream limited.
- **Light** via the Athom WLED controller + SK6812 RGBW-WW panel (344 px, 8×43), ABL capped
  at ~8 A. No separate DMX blinder (Stairville dropped).
- **LoRa receive only** over the RTL-SDR, no active Meshtastic transmit node.
- **Enclosure in ASA**, 3D-printed, 2 parts (split at X=0, 4 mm dowel pins); PLA excluded
  (summer heat). The aluminium plate also serves as a heatsink.
- **Power:** one shared 5 V PSU (Mean Well LRS-150F-5), trimmed to 5.15 V, fused branches;
  230 V separated in its own V-0 enclosure.
- **Dropped:** e-ink display, AS3935 lightning sensor (see README §7).

Detail context for each point in `README.md`.

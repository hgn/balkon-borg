# System design review — Balkon-Borg

Snapshot review as of 2026-07-11. Whole-system evaluation (chassis + carrier PCB +
firmware + requirements). Evaluation only, no changes. Severity: 🔴 critical/high,
🟡 medium, 🟢 low. Domain tags: [Chassis] [PCB] [FW] [System].

## Target system (consolidated)

Ceiling-mounted multifunction unit, front (+Y) to the terrace with the WLED panel
(SK6812 8×43), bottom (−Z) with camera/radar/mic/BME, rear (−Y) to the house with the
boards and connectors. Three nodes: **borg-pi5** (capture + inference), **ESP32 carrier**
(controls + sensing, drives WLED over MQTT only), **nas-Pi5** (always-on remote access +
image storage — the borg-pi5 hosts the broker). One 5 V rail
(Mean Well 30 A) with fused branches. Enclosure SLS/PA12 black, 2 parts (split X=0),
460×148×110.

**Overall verdict:** architecture is clean and consistent — the GPIO map is identical
across board-spec / netlist / firmware, strapping pins are correctly avoided, the power
netclass is technically justified. But there are several concrete defects, one of them
function-critical (ceiling mount). Not yet ready to order.

## 🔴 Critical / high

*Status 2026-07-12: C1, C2, H3, H4 resolved. Medium round: M5 & M12 accepted; M6, M8, M9,
M10, M13 resolved. See the ✅ notes on each.*

**C1 [Chassis] The ceiling screw cannot pass through the ear.**
`EAR_HOLE` is only drilled through the top 6 mm pad (z≈104–110) at x≈−242. Exactly there
the ramp (`RAMP_H`) fills the space below: at x−242 there is solid PA12 from z≈93–104. A
screw driven up into the ceiling hits 11 mm of solid material → **blind hole, mounting
impossible as drawn.**
Fix: run the hole down to the ear underside (length ≈ `RAMP_H+EAR_T`) or move it out to
the thin edge (x≈−254) where there is air under the pad. Plan the head seat from below.
**✅ Resolved:** full through-hole (`EAR_T+RAMP_H`) plus an `EAR_CB_D`=11 mm counterbore
that gives the M5 head a flat, level seat on the sloped underside.

**C2 [Chassis] Front seam unsupported.**
The two halves are bolted only at the rear wall (2 clamps at z28/z82) + 2 dowels. The
**148 mm deep front edges** cantilever free — before the diffuser is glued they gap /
shift. Increasing the depth to 148 mm made this worse.
Fix: add a clamp/snap near the open front (still drivable while the front is open).
**✅ Resolved:** added a front seam clamp on the bottom wall at `FRONT_SEAM_Y`=115 (M3,
clearance/insert like the rear clamps).

**H3 [PCB↔Chassis] Fastener mismatch.**
PCB holes are **M3 (3.2 mm)** (`MountingHole_3.2mm_M3`); the enclosure carrier bosses use
**M2.5 inserts** (`INSERT_M25`). An M3 screw will not fit the M2.5 insert; an M2.5 screw
is sloppy in a 3.2 mm hole. Board-spec point 4 already calls the M3 holes "provisional".
Fix: standardise on M2.5 (the Pi is M2.5 anyway) → PCB holes ~2.7 mm.
**✅ Resolved:** PCB holes are now `MountingHole_2.7mm_M2.5` (place-board.py); the board is
regenerated at layout time.

**H4 [PCB] `ESP_ROW = 25.4` unconfirmed.**
The row spacing of the two 1×19 headers is a placeholder. If wrong, **the DevKit will not
seat**. This is the one real show-stopper dimension before fabrication. Measure on the
real module before the board goes out.
**✅ Resolved:** confirmed **25.4 mm (1 inch)**, the official DevKitC-V4 row spacing
(Espressif docs + the esp32.com thread on exactly this). Kept `ESP_ROW=25.4`; a caliper
check on the actual module is still wise since clones vary.

## 🟡 Medium

**M5 [Chassis/RF] Black PA12 vs radar/WiFi.** If the black is dyed with **carbon black**,
it attenuates the **24 GHz LD2410B** through the 2 mm membrane *and* the 2.4 GHz WiFi of
ESP/WLED through the wall. Many SLS colourings are a dye bath (fine), some are carbon
loaded (bad). Fix: ask the provider about the dyeing method, or measure a membrane
coupon.
**✅ Accepted:** the user treats the damping as uncritical — the radar sees through the
tower wall and WiFi through the plastic is fine as-is.

**M6 [System] Microphone contradiction.** README / use case U6 = **USB microphone**
(BirdNET on the Pi). The enclosure models a **4 mm acoustic port + holder** (electret
capsule). A USB dongle does not mount to a 4 mm hole. Decide: USB mic (cable + tray) or
I²S/electret (then it belongs on the Pi/a board, not a 4 mm hole).
**✅ Resolved:** the mic is a **USB mic on the Pi 5 only**; the 4 mm bottom port + holder
are removed from the enclosure.

**M7 [Chassis/thermal] Intake/exhaust unbalanced.** Intake = large honeycomb field +
bottom holes; exhaust = only **2×2 slits (44×2 mm) per end wall** ≈ 350 mm². For
convection the **exhaust is the bottleneck**, and there is a Pi active cooler + a warm
panel. Fix: enlarge the exhaust area up top significantly.

**M8 [FW] Encoder pins without pull-up.** `rotary_encoder` uses the shorthand
`pin_a: GPIO32 / pin_b: GPIO33` → default **without** internal pull-up. The board has no
external ones (board-spec: "internal pull-up"). EC11 contacts to GND then float. Fix: set
`mode: INPUT_PULLUP` explicitly (already done correctly on the buttons).
**✅ Resolved:** `mode: INPUT_PULLUP` set on both encoder pins.

**M9 [FW] Button LEDs 2 & 3 dead.** `led2`/`led3` are defined as outputs but **never**
switched. Only LED1 (presence) and LED4 (automatic) light. The scene buttons (cozy/party)
stay dark, and there is **no LED for the light on/off state**. UX gap on deliberately
illuminated buttons. Fix: tie the LEDs to preset/state.
**✅ Resolved:** LED2/LED3 now track the active scene (cozy/party) and clear when the
light is turned off.

**M10 [PCB/FW] `RADAR_OUT` (GPIO34) is dead copper.** Wired on the board (220R + connector
pin) but **never used** in firmware (radar runs over UART). Either use it as a fast
presence input or drop it (saves a pin + connector pin + resistor).
**✅ Resolved:** dropped — `J_RADAR` is 4-pin, GPIO34 is free (radar runs over UART).

**M11 [Cost] Depth +50 mm.** For 20 mm of WLED clearance, +50 mm was chosen → ~**+50 %
part volume** in SLS (priced by volume/build box). A deliberate user decision, but the
cost lever is real; relocating the WLED would have cost nothing.

**M12 [Chassis] RTL-SDR free-hanging.** The ~60 mm dongle cantilevers off the Pi USB with
no holder. Knocks/vibration load the USB socket. Fix: clip/rest in the middle bay.
**✅ Accepted:** left as is (no SDR holder) per the user.

**M13 [Chassis] Camera hole may vignette.** 12 mm hole in a 3 mm wall → half-angle ~63°.
Borderline for Camera Module 3 **standard** (66°), too tight for **wide** (120°). Fix:
chamfer/taper the hole or widen it, depending on the lens.
**✅ Resolved:** the lens hole is now **conical** (12 mm inside → 20 mm outside,
`CAM_CHAMFER_D`).

**M14 [System] U5 ADS-B contradictory.** README lists ADS-B as U5; log/build-notes say
"not used". The SDR keep-out is in the enclosure but the purpose is open. Pin down the
scope.

## 🟢 Low / detail

- **L15 [Chassis]** `WALL = 3.0 # ASA` — stale comment, the material is PA12.
- **L16 [Chassis]** The `+X` "HagiOne" and bottom "Balkon Borg" still use
  `CenterOfBoundBox`. The ears reach further in X (x254 > end wall x230) — verify the text
  lands on the end wall and not on a 6 mm ear edge. (The rear texts were moved off this
  exact fragility.)
- **L17 [PCB]** The I²C 4k7 pull-ups are **hard-populated** (not DNP as board-spec
  intends). With a breakout that has its own pull-ups → ~2.3 k in parallel. Works, but
  contradicts the spec.
- **L18 [PCB]** No 5 V bulk cap at `J_PWR` / before the DevKit — with a longer 5 V feed
  (cable inductance / inrush) a 47–100 µF is worthwhile.
- **L19 [Chassis]** The exhaust slit at z=104 can clip the rounded ceiling edge (fillet
  r6, starts ~z104).
- **L20 [FW]** Encoder push = "OFF", button 1 = "toggle" — inconsistent off logic.
- **L21 [FW]** Brightness/state is **open-loop** (local globals). If the WLED app changes
  something, the panel desyncs. Optionally subscribe to the WLED state topic.
- **L22 [Chassis]** No external access to the Pi SD/USB after assembly (the front opens,
  but plan for maintenance).

## What is solid

The GPIO assignment is consistent and **correct** across all three sources (strapping
pins 0/2/5/12/15 and TX0/RX0 cleanly avoided, GND at L14/R1/R7 matches the DevKitC-V4).
The honeycomb keep-out logic against boards/seam is properly verified. The power netclass
(1.0 mm) is correctly justified. The depth check and WLED clearance are now sound.

**Next priorities:** C1 (ear hole) and H4 (ESP_ROW) are fabrication-gating, C2/H3 right
after. The rest is finishing.

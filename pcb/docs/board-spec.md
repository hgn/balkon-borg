# Carrier board specification (`balkon-borg-carrier`)

Sensor/signal carrier of the ESP32 domain. THT, 2 layers, hand-soldered,
fabricated at Aisler. This file is the binding template for the netlist. Net names
and part refs here = net names and refs in the generated schematic/PCB.

For the underlying decisions see `../../log/decisions.md` (entries from 2026-07-10).

## Role and boundaries

- **On the board:** ESP32-DevKitC (socketed), connectors for radar, BME280, encoder,
  4 illuminated buttons, 5 V input; series resistors, LED driver resistors,
  decoupling.
- **Not on the board:** LED panel/WLED (own feed), RTL-SDR, microphone, camera, Pi5
  (all on the Pi or its own bay). No 3.3 V regulator (comes from the DevKit).

## Pin assignment ESP32-DevKitC (proposal, reconcile with ESPHome)

Strapping pins (0, 2, 5, 12, 15) and flash pins (6-11) avoided. Input-only pins
(34-39) only for pure inputs without an internal pull-up.

| Net | GPIO | Dir | Target | Series R | Note |
|---|---|---|---|---|---|
| `RADAR_TX` | 16 (RX2) | in  | LD2410 TX | 220 Ω | UART2 RX |
| `RADAR_RX` | 17 (TX2) | out | LD2410 RX | 220 Ω | UART2 TX |
| `I2C_SDA`  | 21 | bidir | BME280 SDA | – | pull-up 4.7 kΩ (optional, see below) |
| `I2C_SCL`  | 22 | bidir | BME280 SCL | – | pull-up 4.7 kΩ (optional, see below) |
| `ENC_A`    | 32 | in  | encoder A | 100 Ω | internal pull-up |
| `ENC_B`    | 33 | in  | encoder B | 100 Ω | internal pull-up |
| `ENC_SW`   | 25 | in  | encoder button | 100 Ω | internal pull-up |
| `BTN1_SW`  | 13 | in  | button 1 switch | 100 Ω | internal pull-up |
| `BTN2_SW`  | 14 | in  | button 2 switch | 100 Ω | internal pull-up |
| `BTN3_SW`  | 27 | in  | button 3 switch | 100 Ω | internal pull-up |
| `BTN4_SW`  | 26 | in  | button 4 switch | 100 Ω | internal pull-up |
| `BTN1_LED` | 4  | out | NPN Q1 base | 1 kΩ | drives button-1 LED (5 V) low-side |
| `BTN2_LED` | 23 | out | NPN Q2 base | 1 kΩ | drives button-2 LED (5 V) low-side |
| `BTN3_LED` | 18 | out | NPN Q3 base | 1 kΩ | drives button-3 LED (5 V) low-side |
| `BTN4_LED` | 19 | out | NPN Q4 base | 1 kΩ | drives button-4 LED (5 V) low-side |

Used: 15 of the 15 usable bidirectional GPIOs (input-only GPIO34 now free after the
RADAR_OUT drop). Full, but it
fits.

**Button-LED drive:** the 5 V ring LEDs cannot be driven directly from a 3.3 V GPIO.
One NPN per button (BC337-40 / 2N3904, TO-92): LED anode to 5 V, LED cathode to the
collector, emitter to GND, GPIO through 1 kΩ to the base. GPIO high → LED on. The LED
brings its own series resistor (5 V type).

## Connectors (all JST-XH 2.5 mm, THT)

| Ref | Pins | Pinout | Target |
|---|---|---|---|
| `J_PWR`   | 2 | 5V, GND | 5 V feed from the PSU |
| `J_RADAR` | 4 | 5V, GND, `RADAR_RX`(→radar RX), `RADAR_TX`(←radar TX) | LD2410B (HLK breakout) |
| `J_BME`   | 4 | 3V3, GND, `I2C_SCL`, `I2C_SDA` | BME280 |
| `J_ENC`   | 4 | `ENC_A`, `ENC_B`, `ENC_SW`, GND | rotary encoder with button (EC11) |
| `J_BTN1`  | 4 | `BTN1_SW`, GND, 5V, `BTN1_LEDK` | illuminated button 1 |
| `J_BTN2`  | 4 | `BTN2_SW`, GND, 5V, `BTN2_LEDK` | illuminated button 2 |
| `J_BTN3`  | 4 | `BTN3_SW`, GND, 5V, `BTN3_LEDK` | illuminated button 3 |
| `J_BTN4`  | 4 | `BTN4_SW`, GND, 5V, `BTN4_LEDK` | illuminated button 4 |

Per button: `BTNx_SW` (switch → GPIO, other side to GND), 5 V to the LED anode,
`BTNx_LEDK` (LED cathode) back to the collector of the matching NPN. On the cable:
JST-XH crimp housing; buttons with a pigtail or self-crimped.

## Bill of materials (THT)

| Qty | Part | Value/type | Note |
|---|---|---|---|
| 1 | ESP32-DevKitC-V4 (WROOM-32E) | 38-pin, Espressif | external, socketed (not in the Aisler BOM) |
| 2 | female header 1×19 | 2.54 mm | row spacing from the Espressif mechanical drawing |
| 1 | JST-XH header | 2-pin | `J_PWR` |
| 1 | JST-XH header | 4-pin | `J_RADAR` |
| 1 | JST-XH header | 4-pin | `J_BME` |
| 1 | JST-XH header | 4-pin | `J_ENC` |
| 4 | JST-XH header | 4-pin | `J_BTN1..4` |
| 4 | NPN transistor | BC337-40 / 2N3904, TO-92 | button-LED driver Q1..Q4 |
| 2 | resistor | 220 Ω | radar UART TX/RX |
| 7 | resistor | 100 Ω | encoder + button series R |
| 4 | resistor | 1 kΩ | NPN base resistors |
| 2 | resistor | 4.7 kΩ | I²C pull-ups (optional/DNP, see below) |
| 1 | capacitor | 10 µF | 3V3 decoupling |
| 1 | capacitor | 100 nF | 3V3 decoupling |
| 1 | polyfuse | ~2 A resettable | 5 V input (optional, recommended) |

## Open points (to settle before layout)

1. **DevKitC row spacing** — board = Espressif ESP32-DevKitC-V4. KiCad has **no**
   DevKitC footprint → two `PinSocket_1x19_P2.54mm` at **25.4 mm (1 inch)** row spacing
   (`ESP_ROW`), the official DevKitC-V4 value (RESOLVED). A caliper check on the real
   module is still wise, since clones vary.
2. **Button-LED voltage** — model = 12 mm metal, illuminated, **5 V** ring LED. When
   ordering pick the 5 V variant (not 12/24 V); then the NPN driver needs no extra
   resistor.
3. **I²C pull-ups** — provide 4.7 kΩ as **DNP**. Buy a genuine Bosch BME280 (BMP280
   fakes do not measure humidity); typical breakouts have pull-ups on board, so the
   DNP stays empty.
4. **Outline + mounting holes** — outline 150×92 from the enclosure carrier bay; the 4
   corner holes are **M2.5 (2.7 mm, `MountingHole_2.7mm_M2.5`)** to match the enclosure's
   M2.5 carrier inserts (RESOLVED — were M3, which did not fit the inserts).
5. **Connector placement** — the JST header positions follow the cable exits in the
   enclosure; freeze only once the rough layout is set.

**Ergonomics:** the board may be generous (user: big fingers, low dexterity). Space
connectors and holes well apart, easy to grip and solder; do not optimise for minimum
area. See the log entry "Ergonomie".

## PCB review / pre-fab checklist (2026-07-12)

Scope matches the use cases: the board is the **ESP32 domain only** — radar (UART), BME280
(I²C), 4 buttons, encoder, 4 button-LED drivers, 5 V in + F1. SDR/camera/mic/speaker are on
the Pi, correctly **not** on this board. GPIO map is consistent (netlist/firmware), strapping
pins avoided, power netclass (1.0 mm) is sized well above the ~1 A load. Before fabrication:

- ✅ **BC337 pinout** — verified: the KiCad symbol is `Q_NPN_CBE` (pin1=C, 2=B, 3=E) and the
  real BC337 is physically **CBE** (flat face, legs down: C-B-E); the netlist wires C→LED
  cathode, B→1k→GPIO, E→GND (low-side). Just insert the transistor flat-face-to-silk.
- ✅ **ESP DevKitC-V4 header order** — verified: `espR` matches the official V4 right column
  (GND at pins 1/7) and avoids TX0/RX0, strapping and flash pins. Row spacing 25.4 mm
  confirmed. (A caliper check on the actual module is still wise for clones.)
- ✅ **F1 polyfuse footprint** — fixed from an axial-resistor to a radial `FP_PTC`; still
  confirm it matches the actual PTC you buy (PTC packages vary).
- ✅ **DRC to the fab** — `place-board.py` now sets **Aisler** min track/clearance/drill/via/
  annular (also applied to the current board). The 0.2 mm signal / 1.0 mm power widths are
  well within Aisler.
- ✅ **Ground pour + thermal reliefs** — `add-ground-pour.py` (via `make pour`) fills a GND
  pour on both layers with thermal reliefs on the THT pads (0.4 mm gap/spoke); the socketed
  ESP header GND pins bond straight to the plane through their routed tracks.
- ✅ **ESP antenna keep-out** — a no-copper-pour rule area sits under the DevKit's antenna
  end (both layers) so the plane does not detune it.
- ✅ **Fully routed + DRC-clean** — 231 tracks / 3 vias, 0 unconnected, 0 DRC violations
  against the Aisler minimums.
- 🟡 **MCAD collision check** — `make -C pcb step` exports the board STEP; drop it into the
  CadQuery enclosure and confirm connectors/tall parts fit the carrier bay (8 mm standoffs,
  ~100 mm clear to the LED panel — expected OK). This still needs a human eye.
- 🟡 **Connector entry vs cable exits** — J_RADAR → tower (bottom-front), J_BTN → end wall,
  J_BME → bottom; freeze the JST positions/entry direction to match the routing before the
  final board revision.
- 🟢 **Production data** — Gerber + drill via `gen-outputs.py` → Aisler. Hand-soldered THT,
  so no CPL/POS needed; the BOM table above is the assembly list.

## Workflow (scripted, SKiDL)

The board is generated from code, not clicked in the KiCad GUI:

1. `make -C pcb netlist` runs `gen-netlist.py` (SKiDL) → `.net`; `kinet2pcb` turns
   it into a fresh `.kicad_pcb` (footprints, nets taken verbatim).
2. `place-board.py` places the footprints, draws outline + M2.5 holes, sets the
   Aisler DRC minimums, exports a Specctra DSN.
3. Route (Freerouting), then `apply-ses.py` imports the SES back.
4. `make -C pcb pour` adds the GND pour + antenna keep-out (`add-ground-pour.py`,
   three phases). Verify with `kicad-cli pcb drc`.
5. Fabrication data via `make -C pcb outputs`, then upload the Aisler zip.

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
| `RADAR_OUT`| 34 | in  | LD2410 OUT | 220 Ω | input-only ok, radar drives push-pull |
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

Used: 15 of the 15 usable bidirectional GPIOs + 1 input-only (34). Full, but it
fits.

**Button-LED drive:** the 5 V ring LEDs cannot be driven directly from a 3.3 V GPIO.
One NPN per button (BC337-40 / 2N3904, TO-92): LED anode to 5 V, LED cathode to the
collector, emitter to GND, GPIO through 1 kΩ to the base. GPIO high → LED on. The LED
brings its own series resistor (5 V type).

## Connectors (all JST-XH 2.5 mm, THT)

| Ref | Pins | Pinout | Target |
|---|---|---|---|
| `J_PWR`   | 2 | 5V, GND | 5 V feed from the PSU |
| `J_RADAR` | 5 | 5V, GND, `RADAR_RX`(→radar RX), `RADAR_TX`(←radar TX), `RADAR_OUT` | LD2410B (HLK breakout) |
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
| 1 | JST-XH header | 5-pin | `J_RADAR` |
| 1 | JST-XH header | 4-pin | `J_BME` |
| 1 | JST-XH header | 4-pin | `J_ENC` |
| 4 | JST-XH header | 4-pin | `J_BTN1..4` |
| 4 | NPN transistor | BC337-40 / 2N3904, TO-92 | button-LED driver Q1..Q4 |
| 3 | resistor | 220 Ω | UART TX/RX, radar OUT |
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

## Workflow (scripted, SKiDL)

The board is generated from code, not clicked in the KiCad GUI:

1. `make -C pcb netlist` runs `gen-netlist.py` (SKiDL) → netlist/`.kicad_pcb` from
   the tables above; net names taken verbatim.
2. `place-board.py` places the footprints; export a Specctra DSN.
3. Route (Freerouting), then `apply-ses.py` imports the SES back.
4. Set outline/holes once the enclosure is fixed (open points 4/5).
5. Fabrication data via `scripts/gen-outputs.py`, then push/upload to Aisler.

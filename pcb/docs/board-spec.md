# Trägerplatine — Board-Spezifikation (`balkon-borg-carrier`)

Sensor-/Signal-Carrier der ESP32-Domäne. THT, 2-Lagen, selbst gelötet, gefertigt
bei Aisler. Diese Datei ist die verbindliche Vorlage für den Schaltplan im
KiCad-GUI. Netznamen und Bauteil-Refs hier = Netznamen und Refs im Schaltplan.

Grundsatzentscheidungen siehe `../../log/decisions.md` (Einträge vom 2026-07-10).

## Rolle und Grenzen

- **Drauf:** ESP32-DevKitC (gesteckt), Steckverbinder für Radar, BME280, Encoder,
  4 beleuchtete Taster, 5-V-Eingang; Serienwiderstände, LED-Vorwiderstände,
  Entkopplung.
- **Nicht drauf:** LED-Panel/WLED (eigener Strang), RTL-SDR, Mikrofon, Kamera,
  Pi5 (alles am Pi bzw. eigener Kammer). Kein 3,3-V-Regler (kommt vom DevKit).

## Pin-Zuordnung ESP32-DevKitC (Vorschlag, final mit ESPHome abgleichen)

Strapping-Pins (0, 2, 5, 12, 15), Flash-Pins (6–11) gemieden. Input-only-Pins
(34–39) nur für reine Eingänge ohne internen Pull-up.

| Netz | GPIO | Richtung | Ziel | Serien-R | Anmerkung |
|---|---|---|---|---|---|
| `RADAR_TX` | 16 (RX2) | in  | LD2410 TX | 220 Ω | UART2 RX |
| `RADAR_RX` | 17 (TX2) | out | LD2410 RX | 220 Ω | UART2 TX |
| `RADAR_OUT`| 34 | in  | LD2410 OUT | 220 Ω | input-only ok, Radar treibt push-pull |
| `I2C_SDA`  | 21 | bidir | BME280 SDA | – | Pull-up 4,7 kΩ (optional, s.u.) |
| `I2C_SCL`  | 22 | bidir | BME280 SCL | – | Pull-up 4,7 kΩ (optional, s.u.) |
| `ENC_A`    | 32 | in  | Encoder A | 100 Ω | interner Pull-up |
| `ENC_B`    | 33 | in  | Encoder B | 100 Ω | interner Pull-up |
| `ENC_SW`   | 25 | in  | Encoder Taster | 100 Ω | interner Pull-up |
| `BTN1_SW`  | 13 | in  | Taster 1 Schalter | 100 Ω | interner Pull-up |
| `BTN2_SW`  | 14 | in  | Taster 2 Schalter | 100 Ω | interner Pull-up |
| `BTN3_SW`  | 27 | in  | Taster 3 Schalter | 100 Ω | interner Pull-up |
| `BTN4_SW`  | 26 | in  | Taster 4 Schalter | 100 Ω | interner Pull-up |
| `BTN1_LED` | 4  | out | NPN Q1 Basis | 1 kΩ | schaltet Taster-1-LED (5 V) low-side |
| `BTN2_LED` | 23 | out | NPN Q2 Basis | 1 kΩ | schaltet Taster-2-LED (5 V) low-side |
| `BTN3_LED` | 18 | out | NPN Q3 Basis | 1 kΩ | schaltet Taster-3-LED (5 V) low-side |
| `BTN4_LED` | 19 | out | NPN Q4 Basis | 1 kΩ | schaltet Taster-4-LED (5 V) low-side |

Belegt: 15 der 15 gut nutzbaren bidirektionalen GPIOs + 1 input-only (34). Voll,
aber passt.

**Taster-LED-Ansteuerung:** Die 5-V-Ring-LEDs lassen sich nicht direkt vom
3,3-V-GPIO treiben. Je Taster ein NPN (BC337-40 / 2N3904, TO-92): LED-Anode an
5 V, LED-Kathode an Kollektor, Emitter an GND, GPIO über 1 kΩ an die Basis. GPIO
high → LED an. Die LED bringt ihren Vorwiderstand selbst mit (5-V-Typ).

## Steckverbinder (alle JST-XH 2,5 mm, THT)

| Ref | Polzahl | Pinbelegung | Ziel |
|---|---|---|---|
| `J_PWR`   | 2 | 5V, GND | 5-V-Einspeisung vom Netzteil |
| `J_RADAR` | 5 | 5V, GND, `RADAR_RX`(→Radar RX), `RADAR_TX`(←Radar TX), `RADAR_OUT` | LD2410B (HLK-Breakout) |
| `J_BME`   | 4 | 3V3, GND, `I2C_SCL`, `I2C_SDA` | BME280 |
| `J_ENC`   | 4 | `ENC_A`, `ENC_B`, `ENC_SW`, GND | Dreh-Encoder mit Taster (EC11) |
| `J_BTN1`  | 4 | `BTN1_SW`, GND, 5V, `BTN1_LEDK` | beleuchteter Taster 1 |
| `J_BTN2`  | 4 | `BTN2_SW`, GND, 5V, `BTN2_LEDK` | beleuchteter Taster 2 |
| `J_BTN3`  | 4 | `BTN3_SW`, GND, 5V, `BTN3_LEDK` | beleuchteter Taster 3 |
| `J_BTN4`  | 4 | `BTN4_SW`, GND, 5V, `BTN4_LEDK` | beleuchteter Taster 4 |

Je Taster: `BTNx_SW` (Schalter → GPIO, andere Seite auf GND), 5 V an die LED-Anode,
`BTNx_LEDK` (LED-Kathode) zurück auf den Kollektor des zugehörigen NPN. Am Kabel:
JST-XH-Crimpgehäuse; Taster mit Kabelschwanz oder selbst gecrimpt.

## Stückliste (THT)

| Menge | Bauteil | Wert/Typ | Anmerkung |
|---|---|---|---|
| 1 | ESP32-DevKitC-V4 (WROOM-32E) | 38-Pin, Espressif | extern, gesteckt (nicht im Aisler-BOM) |
| 2 | Buchsenleiste 1×19 | 2,54 mm | Reihenabstand aus Espressif-Mechanikzeichnung |
| 1 | JST-XH Wanne | 2-pol | `J_PWR` |
| 1 | JST-XH Wanne | 5-pol | `J_RADAR` |
| 1 | JST-XH Wanne | 4-pol | `J_BME` |
| 1 | JST-XH Wanne | 4-pol | `J_ENC` |
| 4 | JST-XH Wanne | 4-pol | `J_BTN1..4` |
| 4 | NPN-Transistor | BC337-40 / 2N3904, TO-92 | Taster-LED-Treiber Q1..Q4 |
| 3 | Widerstand | 220 Ω | UART TX/RX, Radar OUT |
| 7 | Widerstand | 100 Ω | Encoder + Taster Serien-R |
| 4 | Widerstand | 1 kΩ | NPN-Basiswiderstände |
| 2 | Widerstand | 4,7 kΩ | I²C-Pull-ups (optional/DNP, s.u.) |
| 1 | Kondensator | 10 µF | 3V3-Entkopplung |
| 1 | Kondensator | 100 nF | 3V3-Entkopplung |
| 1 | Polyfuse | ~2 A rückstellend | 5-V-Eingang (optional, empfohlen) |

## Offene Punkte (vor dem Layout zu klären)

1. **DevKitC-Reihenabstand** — Board = Espressif ESP32-DevKitC-V4. KiCad hat
   **keinen** DevKitC-Footprint → zwei `PinSocket_1x19_P2.54mm` platzieren, exakten
   Reihenabstand aus der Espressif-Mechanikzeichnung vor dem Layout eintragen.
2. **Taster-LED-Spannung** — Modell = 12-mm-Metall, beleuchtet, **5-V**-Ring-LED.
   Beim Bestellen die 5-V-Variante wählen (nicht 12/24 V); dann passt der
   NPN-Treiber ohne zusätzlichen Vorwiderstand.
3. **I²C-Pull-ups** — 4,7 kΩ als **DNP** vorsehen. Echtes Bosch-BME280 kaufen
   (BMP280-Fälschungen messen keine Feuchte); übliche Breakouts haben Pullups an
   Bord, DNP bleibt dann leer.
4. **Außenkontur + Befestigungslöcher** — kommen aus dem CadQuery-Gehäuse (noch
   nicht vermessen). Bis dahin Platzhalterkontur, 4× M3-Löcher provisorisch.
5. **Stecker-Platzierung** — Position der JST-Wannen richtet sich nach den
   Kabelabgängen im Gehäuse; erst mit der Grobanordnung einfrieren.

**Ergonomie:** Board darf großzügig sein (Nutzer: große Finger, ungeschickt).
Stecker und Löcher weit auseinander, bequem zu greifen und zu löten; nicht auf
Minimalfläche optimieren. Siehe Log-Eintrag "Ergonomie".

## KiCad-Workflow (kurz)

1. In KiCad neues Projekt `balkon-borg-carrier` in diesem `pcb/`-Verzeichnis.
2. Schaltplan nach den Tabellen oben; Netznamen exakt übernehmen.
3. ERC sauber, dann Footprints zuweisen, Netzliste → PCB.
4. Kontur/Löcher erst setzen, wenn das Gehäuse steht (Offene Punkte 4/5).
5. Fertigungsdaten via `scripts/gen-outputs.py`, dann Push/Upload zu Aisler.

# Balkon-Borg — Projektüberblick

*Smarte, teils selbstgebaute Multifunktionseinheit unter dem Balkon, angebunden ans Heimnetz und an den Raspberry-Pi-Homeserver.*

---

## Preview

Enclosure (SLS/PA12, rounded edges, ceiling-mount ears, slogans embossed) and the
ESP32 sensor carrier board (fully placed and routed):

![Enclosure](docs/img/enclosure.png)

![Carrier board](docs/img/pcb-top.png)

---

## 1 · Kurzbeschreibung

Ein kompaktes Gehäuse, das unter dem Balkon (über der Terrasse, ~2 m vom Esstisch) verschraubt wird und mehrere Funktionen bündelt: stimmungsvolle bis partytaugliche Beleuchtung, Präsenz- und Umwelterkennung, Flugzeug-Empfang (ADS-B) und Vogelstimmen-Erkennung. Alles läuft über einen gemeinsamen 5-V-Strang und einen MQTT-/WLAN-Bus zusammen. Ziel ist ein Aufbau, der nach *Absicht* aussieht (ein Kasten, ein Lichtfeld, minimale Kabel) statt nach Bastelei.

## 2 · Ziele

- **Ein sichtbarer Kasten, minimale Kabel** — genau eine 230-V-Zuleitung, alles Weitere 5 V + Funk.
- **Mehrwert statt Spielerei** — Automatiken und Daten, die im Alltag tatsächlich genutzt werden (Licht am Tisch, Wetter, Vögel, Flieger).
- **Sauber ins bestehende Setup integriert** — MQTT-Bus, Podman/Quadlets auf dem NAS-Pi, Netdata/Grafana.
- **Wartbar und erweiterbar** — lötarme, vorgeflashte Komponenten; Gehäuse als parametrischer Code (CadQuery), nicht als Einweg-Klickmodell.
- **Robuster Dauerbetrieb im Freien** (geschützt) — thermisch und elektrisch auf Sommerbetrieb ausgelegt.

## 3 · Use Cases

| # | Use Case | Realisierung |
|---|---|---|
| U1 | Licht am Esstisch, abends automatisch | SK6812-RGBW-Panel (WLED) + LD2410B-Radar → sanftes Anfahren bei Präsenz, Warmweiß-Kanal |
| U2 | Manuelle Lichtsteuerung ohne Handy | 4× Edelstahltaster + Drehencoder (an/aus, Szenen, Dimmen, Automatik-Pause) |
| U3 | Effekt-/Party-Licht | WLED-2D-Effekte, Strobe, Lauftext auf der 8×43-Matrix |
| U4 | Umweltdaten | BME280 (Temperatur/Feuchte/Druck) → MQTT → Dashboard |
| U5 | Flugzeug-Empfang | RTL-SDR V3 + readsb/tar1090 (Anflug MUC, optional Feed) |
| U6 | Vogelstimmen-Log | USB-Mikrofon → BirdNET → Artenstatistik über die Saison |
| U7 | Kamera + lokale Erkennung | Camera Module 3 → Frigate (Personen/Tiere) **auf Pi-5-CPU** |
| U8 | Passiver Funk-Mithör (optional) | LoRa/Meshtastic **RX** über den SDR (kein aktiver Sendeknoten) |

## 4 · Systemkomponenten (Ist-Stand)

- **Edge-Compute:** Raspberry Pi 5 (8 GB) + Active Cooler, microSD — Aufnahme (Kamera/Audio/SDR) und lokale Inferenz (Frigate, readsb).
- **Sensor-/Bedien-Frontplatte:** ESP32 (ESPHome) mit LD2410B (UART), BME280 (I²C), 4 Taster + Encoder (GPIO).
- **Licht:** Athom High-Power-WLED-Controller + SK6812-RGBW-WW-Kompaktpanel (8 Reihen × 43 = 344 px) auf 3-mm-Alu-Platte, Opal-Acryl-Diffusor.
- **Empfang:** RTL-SDR V3 (ADS-B 1090 MHz, optional LoRa-RX), USB-Mikrofon.
- **Strom:** Mean Well LRS-150F-5 (5 V/22 A) im eigenen V-0-Gehäuse, abgesicherte Abgänge.
- **Gehäuse:** 3D-Druck in ASA, 2-teilig (Druckbett-Split mit Passstiften); Alu-Platte = Front + Kühlkörper.
- **Backend (vorhanden):** NAS-Pi 5 mit Mosquitto (MQTT-Broker), tar1090, BirdNET-Go, Dashboards/Storage.

## 5 · Architektur & Datenfluss

Der **Edge-Pi 5** erfasst Kamera (CSI), Audio (USB) und HF (USB-SDR) und rechnet die Objekterkennung lokal — nur Events und Metadaten gehen per MQTT weiter, kein Dauer-Rohstream. Der **ESP32** bedient die menschennahe, echtzeitkritische I/O (Taster, Encoder, Radar) und die trägen Umweltsensoren; er ist bewusst die *billige, austauschbare Frontplatte*, die den teuren Rechenknoten vor der langen Außenverkabelung schützt und ihn entlastet. Der **NAS-Pi 5** ist Broker, Dashboard- und Storage-Ebene. Kopplung durchgängig über **WLAN/MQTT** (Ethernet optional).

## 6 · Randbedingungen

**Umgebung**
- Montageort Balkonunterseite: **regengeschützt**, aber erhöhte Luftfeuchte möglich; Münchner **Sommerhitze** relevant.
- Kein echtes IP65 nötig (geschützte Lage) → **belüftetes** Gehäuse mit Schlitzen nach unten + Insektenschutz.

**Elektrik**
- Genau **eine 230-V-Zuleitung** (Terrassensteckdose, FI-geschützt); Zielbild „keine tausend Kabel".
- Ein gemeinsames **5-V-Netzteil**, abgesicherte Abgänge (10 A LED / 5 A Pi / 2 A Kleinelektronik), gemeinsames GND, Trimmer auf **5,15 V**.
- **Brandschutz:** 230-V-Netzteil **getrennt** vom FDM-Druckteil (eigenes V-0-/Metallgehäuse); Druckteil führt nur Niedervolt.

**Thermik**
- **Alu-Platte = Kühlkörper** der LED-Ebene, thermischer Kontakt zum Gehäuse (Wärmeleitpad an den Auflagen).
- Pi-5-Dauerlast (jetzt inkl. **CPU-Objekterkennung**) → Active Cooler + Belüftung sind kritisch, nicht optional.
- WLED **Automatic Brightness Limiter** auf ~8 A → begrenzt Wärme und Strom des Panels.

**Mechanik / Fertigung**
- **3D-Druck in ASA** (UV-/wärmefest bis ~95 °C); PLA scheidet aus.
- Teile > 256 mm Kantenlänge → **gesplittet** (X=0) mit 4-mm-Passstiften; STEP an den Druckdienst (JLC3DP/Craftcloud, alternativ FabLab München).
- Radar sieht durch **2-mm-Membran**; Kamera/Mikro-Durchbrüche integriert.

**Netzwerk**
- WLAN + MQTT als Bus; **Ethernet optional** (macht nur den Videostream bombenfester).

**Skill-Level / Präferenzen**
- Löten und Programmieren vorhanden, **kein Vollbastler** → lötfreie/vorgeflashte Teile bevorzugt (Athom vorgeflasht, steckbare LED-Verbinder, Taster mit Kabelschwanz).
- **Qualität vor Preis** — spiegelt sich in RGBW-WW (echtes Warmweiß), Edelstahltastern, ASA.

**Budget**
- **~415 €** Neuteile + **~40 €** Kleinkram (Verbinder, Sicherungen, Wago, Litze, Schrauben, Inserts, Verschraubungen). Kamera und NAS-Pi bereits vorhanden.

## 7 · Bewusst nicht im Scope (mit Konsequenz)

| Gestrichen | Konsequenz |
|---|---|
| **E-Ink-Statusdisplay** | Datenanzeige nur über bestehende Dashboards (Grafana/tar1090). |
| **AI HAT / Hailo-NPU** | Objekterkennung läuft auf der **Pi-5-CPU** (ein Kamerastream ok, geringere FPS); jederzeit **nachrüstbar**, PCIe-Port bleibt frei (optional NVMe-SSD). |
| **Heltec / aktiver Meshtastic-Knoten** | LoRa nur **empfangen** über den SDR, kein Senden ins Mesh. |
| **AS3935-Blitzsensor** | Keine lokale Gewitterfrüherkennung. |
| **Stairville Wild Wash + USB-DMX** | Kein separater Blinder; Effekt-/Strobe-Licht kommt aus dem WLED-Panel selbst. |

## 8 · Offene Punkte / nächste Schritte

1. **Klemmenbelegung** — konkrete ESP32-GPIOs, I²C-Adressen (BME280), Wago-Plan der 5-V-Verteilung.
2. **Podman-Quadlets** — Mosquitto, Frigate (CPU-Detektor), readsb/tar1090, BirdNET-Go.
3. **Reale Board-Vermessung** → Montagedom-Positionen in `balkon_borg.py` (CadQuery) anpassen.
4. **WLED-Konfig** — 2D 43×8 Serpentine, ABL auf 8 A, Presets/Szenen + Taster-Mapping.
5. **Netzteil** — EEPROM `PSU_MAX_CURRENT=5000`, Ausgang auf 5,15 V trimmen.
6. **Passungstest** — Ecke/Braue drucken (Insert- und Diffusor-Nut-Passung) vor den großen Hälften.

## 9 · Wesentliche Risiken

- **Thermik im Sommer** — CPU-Detection erhöht die Dauerlast; Belüftung und Active Cooler entscheiden über Stabilität.
- **Erkennungsleistung** — ohne NPU FPS-/Stream-begrenzt; ggf. leichteres Modell oder späteres Hailo-Retrofit.
- **Feuchte/Kondensat** — Belüftung nach unten und ggf. Druckausgleich beachten, damit sich nichts sammelt.

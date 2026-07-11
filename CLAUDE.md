# CLAUDE.md — Balkon-Borg

Projektspezifischer Arbeitskontext. Ergänzt die globalen Konventionen aus
`~/.claude/CLAUDE.md` (Sprache, Dateinamen mit `-`, Make-Standardziele, Python-
und C-Stil, Git-Konventionen). Bei Konflikt gewinnen die globalen Regeln, sofern
hier nicht bewusst abgewichen wird.

## Immer zuerst lesen

1. Dieses File.
2. `log/decisions.md` — das Entscheidungslog. Enthält, *warum* der Aufbau so ist,
   wie er ist. Bevor du eine Designfrage neu diskutierst, prüfe, ob sie dort
   schon entschieden wurde.
3. `README.md` bei Bedarf für den vollständigen Projektüberblick (Use Cases U1–U8,
   Komponenten, Randbedingungen, Scope-Grenzen).

## Was das hier ist

Hardware-plus-Software-Bastelprojekt: eine Multifunktionseinheit unter dem
Balkon. Ein Gehäuse bündelt Licht (WLED-Panel), Präsenz-/Umweltsensorik (ESP32),
Empfang (RTL-SDR, Mikrofon) und Kamera, angebunden per WLAN/MQTT an einen
NAS-Pi. Details in `README.md`.

Es gibt drei Rechenknoten mit klarer Rollentrennung:
- **Edge-Pi 5** — Aufnahme (Kamera/Audio/SDR) und lokale Inferenz (Frigate,
  readsb, BirdNET). Nur Events/Metadaten per MQTT, kein Dauer-Rohstream.
- **ESP32 (ESPHome)** — echtzeitnahe I/O (Taster, Encoder, LD2410B-Radar) und
  träge Umweltsensoren (BME280). Bewusst die billige, austauschbare Frontplatte.
- **NAS-Pi 5** — MQTT-Broker (Mosquitto), Dashboards, Storage. Bereits vorhanden.

## Teilbereiche und wo ihr Zeug hingehört

Das Projekt hat mehrere Domänen. Beim Anlegen neuer Artefakte die Domäne treffen:

| Domäne | Werkzeug / Format | geplanter Ort |
|---|---|---|
| Gehäuse (CAD) | CadQuery (Python), parametrisch, Export STEP/STL | `cad/balkon_borg.py` |
| Trägerplatine (Sensor-Carrier) | KiCad (GUI) → Aisler; Python nur für Output/DRC/BOM | `pcb/` |
| ESP32-Firmware | ESPHome (YAML) | `firmware/esphome/` |
| Licht | WLED-Konfig, Presets, Taster-Mapping | `wled/` |
| Backend-Dienste | Podman-Quadlets (Mosquitto, Frigate, readsb/tar1090, BirdNET-Go) | `deploy/quadlets/` |
| Verdrahtung | Klemmenbelegung, GPIO-/I²C-/Wago-Plan | `docs/wiring.md` |

Verzeichnisse erst anlegen, wenn der erste echte Inhalt entsteht, nicht auf Vorrat.

## Wichtige Doku-Dateien

- **[`docs/enclosure-sintering.md`](docs/enclosure-sintering.md)** — Gehäuse-Fertigung:
  **SLS/PA12 schwarz**, SLS-Designregeln, Druckteile, Anbieter (JLC3DP/Craftcloud/…).
- [`docs/build-notes.md`](docs/build-notes.md) — Integration/Bau (Pi5-Strom, ESP-Flash,
  WLAN, Druck, Hardware-Checkliste).
- [`docs/power-distribution.md`](docs/power-distribution.md) — 5-V-Stern + Abzweigsicherungen.
- [`pcb/docs/board-spec.md`](pcb/docs/board-spec.md) — verbindliche Board-Vorlage.

## Konventionen für dieses Projekt

- **Doku und Prosa auf Deutsch** (Projektsprache), **Code/Bezeichner/Kommentare
  auf Englisch** gemäß globaler Regel. Program-Output Englisch.
- **CAD ist Code, kein Klickmodell**: `cad/balkon_borg.py` bleibt parametrisch.
  Reale Maße (Board-Vermessung, Insert-/Diffusor-Passung) als benannte Parameter
  oben im File, nicht als Magic Numbers im Body.
- **Maße metrisch**, mm als Default-Einheit im CAD. Toleranzen dokumentieren.
- **Sicherheit ist nicht verhandelbar**: 230 V strikt getrennt vom gedruckten
  Gehäuse (Netzteil extern). Druckteil führt nur Niedervolt. Bei jedem
  Elektrik-/Thermik-Vorschlag Brandschutz und Absicherung mitdenken.
- **MQTT** ist der Bus. Neue Datenquellen bekommen ein klares Topic-Schema;
  Schema im Log festhalten, sobald es steht.
- **Lötarm bevorzugt**: vorgeflashte/steckbare Teile vor Selbstbau, solange
  Qualität stimmt (Präferenz: Qualität vor Preis).
- **Großzügig dimensionieren (Ergonomie).** Der Nutzer hat große Finger und ist
  eher ungeschickt: Board und Gehäuse dürfen ruhig größer sein. Bedienelemente,
  Stecker und Schrauben weit auseinander, keine gedrängten Layouts oder fummelige
  Mikroverbinder, keine dichte Handlöterei. Im Zweifel größer statt kompakter.

## Entscheidungslog pflegen (wichtig)

Sobald eine nicht-triviale Entscheidung fällt (Bauteilwahl, GPIO-Belegung,
Topic-Schema, Maß-/Toleranzfestlegung, Scope-Änderung, verworfene Alternative),
**hängst du einen datierten Eintrag an `log/decisions.md` an**. Format und Beispiel
stehen im Kopf dieses Files. Das Log ist die Gedächtnisschicht des Projekts: es
verhindert, dass bereits geklärte Fragen erneut aufgerollt werden.

Nicht loggen, was ohnehin im Code/YAML steht. Loggen, *warum* es so ist und
welche Alternative aus welchem Grund verworfen wurde.

## Nächste Schritte

Aktueller Stand und offene Punkte: siehe `README.md` §8 und die jüngsten
Einträge in `log/decisions.md`.

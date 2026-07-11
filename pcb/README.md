# pcb — Trägerplatine (Sensor-Carrier)

ESP32-Frontplatine, THT, 2-Lagen, gefertigt bei Aisler. Verbindliche Vorlage:
[`docs/board-spec.md`](docs/board-spec.md). Entscheidungen im Projekt-Log
(`../log/decisions.md`).

## Ablauf (Netzliste per Code, Layout im KiCad)

Die Schaltung inklusive der korrekten ESP32-DevKitC-V4-Pinzuordnung wird als Code
beschrieben und daraus eine KiCad-Netzliste erzeugt. Du machst nur das Layout.

1. **Netzliste erzeugen** (schon geschehen, bei Änderungen neu):
   ```
   KICAD9_SYMBOL_DIR=/usr/share/kicad/symbols \
   KICAD9_FOOTPRINT_DIR=/usr/share/kicad/footprints \
   ../.venv/bin/python gen-netlist.py      # -> balkon-borg-carrier.net
   ```
2. **In KiCad importieren:** KiCad → **PCB-Editor** (Pcbnew) öffnen →
   *Datei → Importieren → Netzliste…* → `balkon-borg-carrier.net` wählen →
   *Aktuelles PCB aktualisieren*. Alle 33 Bauteile erscheinen mit Footprints.
3. **Layout:** Bauteile auseinanderziehen, Außenkontur auf `Edge.Cuts` zeichnen
   (kommt später aus der Carrier-Bucht des Gehäuses), Stecker an die Ränder,
   Leiterbahnen ziehen (2 Lagen, großzügig). Ergonomie: viel Abstand.
4. **DRC** sauber, dann Fertigungsdaten:
   ```
   ../.venv/bin/python scripts/gen-outputs.py balkon-borg-carrier.kicad_pcb
   ```
5. Gerber-Zip zu **Aisler** hochladen (oder KiCad-Push).

## Dateien

- `gen-netlist.py` — SKiDL-Skript, erzeugt die Netzliste aus `docs/board-spec.md`.
- `balkon-borg-carrier.net` — generierte KiCad-Netzliste (Import-Quelle).
- `scripts/gen-outputs.py` — Fertigungsoutput via `kicad-cli`.

## Konventionen

Doku deutsch, Netznamen/Bezeichner englisch. THT-only, JST-XH 2,5 mm, großzügige
Abstände. Änderungen an der Schaltung immer in `gen-netlist.py`, dann Netzliste neu
erzeugen und in KiCad *Netzliste importieren* wiederholen (aktualisiert das PCB).

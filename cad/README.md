# cad — Gehäuse (CadQuery)

Parametrisches, deckenmontiertes Gehäuse. Panel zeigt nach unten, Bedienung an der
Seite, Deckenbefestigung über seitliche Nasen. Grundsatzentscheidungen im
Projekt-Log (`../log/decisions.md`).

## Werkzeug

CadQuery in einem projektlokalen venv (`../.venv`, nicht eingecheckt). Einmalig:

```
python3 -m venv ../.venv && ../.venv/bin/pip install cadquery matplotlib
```

## Bauen und ansehen

```
../.venv/bin/python balkon_borg.py                       # STEP/STL nach build/
../.venv/bin/python preview.py build/balkon-borg-body.stl # PNG-Vorschau
```

`balkon_borg.py` exportiert `balkon-borg-body`, `-left`, `-right` (Druckbett-Split
bei X=0) als STEP (für den Druckdienst) und STL. Alle Maße stehen als Parameter
oben im Skript; der LED-Panel-Pitch ist eine Annahme und skaliert das Ganze.

## Offene Modell-Punkte

Front-Rebate für die Alu-Platte, Kamera-/Radar-/Mikro-Durchbrüche, Diffusor-Nut,
Insektengitter, Ohr-Gussets. Die Alu-Frontplatte wird ein eigenes Teil.

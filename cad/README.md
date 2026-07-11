# cad — Enclosure (CadQuery)

Parametric, ceiling-mounted enclosure. The LED panel faces forward to the terrace,
controls sit on the side wall, ceiling mounting via side-wall ears. Manufactured by
SLS in PA12 (see `../docs/enclosure-sintering.md`). Design rationale is in the
project log (`../log/decisions.md`).

## Tooling

CadQuery in a project-local venv (`../.venv`, not committed). One-time setup:

```
python3 -m venv ../.venv && ../.venv/bin/pip install cadquery matplotlib
```

## Build and view

```
make all                 # from the repo root: cleans, then builds cad/build/
make -C cad all          # just the enclosure
../.venv/bin/python balkon_borg.py            # or run it directly
../.venv/bin/python preview.py build/balkon-borg-body.stl   # quick matplotlib preview
```

`balkon_borg.py` exports `balkon-borg-body`, `-left`, `-right` (the print-bed split
at X=0) as STEP (for the print service) and STL. All dimensions are parameters at
the top of the script; the LED panel pitch is an assumption and scales the whole
enclosure.

## Open model items

Front rebate details for the glued diffuser/panel, exact camera/radar/mic openings
against the real parts, WLED cradle size, and soft radii at the ear roots and vent
slits.

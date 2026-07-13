# Image sources / provenance

Every image in this folder is **generated from a source of truth in the repo** — none is
hand-drawn or edited by hand. This table says exactly what each image is derived from and
how to regenerate it, so it is always unambiguous what comes from where.

| Image | Shows | Derived from (source of truth) | Tool | Regenerate |
|---|---|---|---|---|
| `enclosure.png` | Enclosure, iso view | `cad/balkon_borg.py` → `cad/build/balkon-borg-body.stl` | CadQuery build + `f3d` render | build STL, then `f3d … --output docs/img/enclosure.png` |
| `enclosure.stl` | Enclosure mesh | `cad/balkon_borg.py` | CadQuery (`cq.exporters`) | `python cad/balkon_borg.py`, copy `build/balkon-borg-body.stl` |
| `pcb-top.png` | Routed carrier board, top | `pcb/balkon-borg-carrier.kicad_pcb` | `kicad-cli pcb render --side top` | `kicad-cli pcb render … -o pcb/board-top.png`, copy here |
| `wiring-harness.png` / `.svg` | Cable harness: board connectors → external parts, with pinout + wire colours | `pcb/wiring-harness.yaml` (itself derived from `pcb/gen-netlist.py` / `board-spec.md`) | **WireViz** → GraphViz `dot -Gdpi=300` | `make -C pcb harness` |
| `board-annotated.png` | The board render with callouts to each external component | `pcb/board-top.png` (the `pcb-top.png` render) **+** `pcb/annotate-board.py` (connector positions from `place-board.py`) | matplotlib overlay | `make -C pcb harness` |

## Chain of derivation

```
cad/balkon_borg.py ─► build/*.stl ─► enclosure.png / enclosure.stl
pcb/gen-netlist.py ─► kicad_pcb ─► kicad-cli render ─► pcb-top.png ─┐
pcb/place-board.py (connector mm) ─────────────────────────────────┼─► board-annotated.png
pcb/gen-netlist.py / board-spec.md ─► pcb/wiring-harness.yaml ─► WireViz ─► wiring-harness.png/.svg
```

The two wiring images (`wiring-harness.*` and `board-annotated.png`) show the **same
connections** two ways: WireViz is the schematic harness (pinout + wire colours, the
colours are a suggested convention), the annotated render is "where it physically sits on
the board". Both trace back to the netlist, so they cannot silently disagree with the
board.

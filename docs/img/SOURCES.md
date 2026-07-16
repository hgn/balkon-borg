# Image sources / provenance

Every image in this folder is **generated from a source of truth in the repo** — none is
hand-drawn or edited by hand. This table says exactly what each image is derived from and
how to regenerate it, so it is always unambiguous what comes from where.

| Image | Shows | Derived from (source of truth) | Tool | Regenerate |
|---|---|---|---|---|
| `enclosure.png` | Enclosure, iso view | `cad/balkon_borg.py` → `cad/build/balkon-borg-body.stl` | CadQuery build + `f3d` render | build STL, then `f3d … --output docs/img/enclosure.png` |
| `enclosure.stl` | Enclosure mesh | `cad/balkon_borg.py` | CadQuery (`cq.exporters`) | `python cad/balkon_borg.py`, copy `build/balkon-borg-body.stl` |
| `pcb-top.png` | Routed carrier board, top | `pcb/balkon-borg-carrier.kicad_pcb` | `kicad-cli pcb render --side top` | `kicad-cli pcb render … -o pcb/board-top.png`, copy here |
| `overview.png` | Enclosure, four line-art views | `cad/balkon_borg.py` → STEP | FreeCAD TechDraw projection + matplotlib | `make -C cad views` |

The board-specific **wiring images** (`wiring-harness.*`, `board-annotated.png`) moved to
[`../../pcb/docs/img/`](../../pcb/docs/img/) — see [`pcb/README.md`](../../pcb/README.md#wiring).

## Chain of derivation

```
cad/balkon_borg.py ─► build/*.stl ─► enclosure.png / enclosure.stl / overview.png
pcb/gen-netlist.py ─► kicad_pcb ─► kicad-cli render ─► pcb-top.png
```

# pcb — Sensor carrier board (KiCad)

The ESP32 front panel: THT, 2 layers, made at Aisler. Binding source of truth:
[`docs/board-spec.md`](docs/board-spec.md). Decisions are in the project log
(`../log/decisions.md`).

## Flow (netlist from code, layout scripted)

The schematic — including the correct ESP32-DevKitC-V4 pin mapping — is described in
code and turned into a KiCad netlist; placement and routing are scripted so the
board is reproducible.

1. **Netlist** from `gen-netlist.py` (SKiDL) → `balkon-borg-carrier.net`:
   ```
   make -C pcb netlist
   ```
2. **Import** the netlist into a fresh `balkon-borg-carrier.kicad_pcb` with
   `kinet2pcb` (footprints + nets), or start from the committed board.
3. **Place + route** (one-time, headless): `place-board.py` lays out the footprints,
   draws the outline, adds the mounting holes and the "HagiOne" silkscreen, sets the
   Aisler DRC minimums, exports a Specctra DSN; Freerouting autoroutes it;
   `apply-ses.py` imports the session back. (Freerouting is an external tool, not
   vendored.)
4. **Ground pour**:
   ```
   make -C pcb pour           # GND pour (both layers) + antenna keep-out
   ```
5. **Fabrication outputs**:
   ```
   make -C pcb outputs        # gerbers/drill/pos + Aisler zip into output/
   ```
   The committed board is fully routed and DRC-clean (0 violations, 0 unconnected).
6. Upload the gerber zip to **Aisler**.

## Files

- `gen-netlist.py` — SKiDL script, builds the netlist from `docs/board-spec.md`.
- `place-board.py` / `apply-ses.py` — headless placement and Specctra-session import
  (run with the system python, which has the KiCad `pcbnew` module).
- `add-ground-pour.py` — GND pour + antenna keep-out, run in three phases (`make pour`);
  the phases must be separate processes (pcbnew drops the rule area otherwise).
- `scripts/gen-outputs.py` — fabrication output via `kicad-cli`.

## Conventions

Comments/net names in English. THT only, JST-XH 2.5 mm, generous spacing. Change the
schematic only in `gen-netlist.py`, then regenerate the netlist and re-import.

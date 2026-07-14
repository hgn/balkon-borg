# Carrier board (KiCad). Placement + routing is a one-time step done with the
# scripts / KiCad (see README); these targets regenerate the reproducible parts:
# the netlist from source and the fabrication outputs from the committed board.
PY := ../.venv/bin/python
KENV := KICAD9_SYMBOL_DIR=/usr/share/kicad/symbols \
        KICAD9_FOOTPRINT_DIR=/usr/share/kicad/footprints

SYSPY := /usr/bin/python3       # KiCad pcbnew module lives in the system python
WIREVIZ := ../.venv/bin/wireviz
.PHONY: all netlist verify pour outputs step harness clean
all: outputs                   ## generate fabrication outputs from the committed board

netlist:                       ## regenerate the KiCad netlist (then re-import in KiCad)
	$(KENV) $(PY) gen-netlist.py

verify:                        ## automated pre-order check: ERC, DRC, netlist<->board, spec, outputs
	$(SYSPY) verify.py

pour:                          ## add the GND pour + antenna keep-out (3 separate phases)
	$(SYSPY) add-ground-pour.py --pours
	$(SYSPY) add-ground-pour.py --rulearea
	$(SYSPY) add-ground-pour.py --fill

outputs:                       ## gerbers/drill/pos + Aisler zip into output/
	$(PY) scripts/gen-outputs.py balkon-borg-carrier.kicad_pcb

step:                          ## export board as STEP for the MCAD collision check
	@mkdir -p output
	kicad-cli pcb export step balkon-borg-carrier.kicad_pcb \
	    -o output/balkon-borg-carrier.step --subst-models --no-dnp

harness:                       ## wiring diagram (WireViz -> 300 dpi PNG) + annotated board
	$(WIREVIZ) -f gs wiring-harness.yaml
	dot -Tpng -Gdpi=300 wiring-harness.gv -o wiring-harness.png
	$(PY) annotate-board.py         # needs board-top.png (kicad-cli render) present
	cp wiring-harness.png wiring-harness.svg board-annotated.png ../docs/img/

clean:                         ## remove generated outputs, netlists and caches
	rm -rf output __pycache__ *.net *.dsn *.ses *.rpt *-backups \
	       fp-info-cache logs gen-netlist.erc gen-netlist.log gen-netlist_sklib.py \
	       wiring-harness.gv wiring-harness.png wiring-harness.svg board-annotated.png

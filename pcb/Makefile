# Carrier board (KiCad). Placement + routing is a one-time step done with the
# scripts / KiCad (see README); these targets regenerate the reproducible parts:
# the netlist from source and the fabrication outputs from the committed board.
PY := ../.venv/bin/python
KENV := KICAD9_SYMBOL_DIR=/usr/share/kicad/symbols \
        KICAD9_FOOTPRINT_DIR=/usr/share/kicad/footprints

.PHONY: all netlist outputs clean
all: outputs                   ## generate fabrication outputs from the committed board

netlist:                       ## regenerate the KiCad netlist (then re-import in KiCad)
	$(KENV) $(PY) gen-netlist.py

outputs:                       ## gerbers/drill/pos + Aisler zip into output/
	$(PY) scripts/gen-outputs.py balkon-borg-carrier.kicad_pcb

clean:                         ## remove generated outputs, netlists and caches
	rm -rf output __pycache__ *.net *.dsn *.ses *.rpt *-backups \
	       fp-info-cache logs gen-netlist.erc gen-netlist.log gen-netlist_sklib.py

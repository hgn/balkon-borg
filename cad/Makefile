# Enclosure (CadQuery). `make all` cleans, then rebuilds STEP + STL into build/.
PY := ../.venv/bin/python
OVERVIEW := ../docs/img/overview.png

.PHONY: all clean views preview help

all: clean                     ## clean then build the enclosure halves (STEP + STL)
	$(PY) balkon_borg.py

views: all                     ## build, then render docs/img/overview.png (needs FreeCAD)
	freecadcmd freecad-views.py
	$(PY) render-views.py

preview: views                 ## render the overview and open it
	xdg-open $(OVERVIEW) 2>/dev/null || true

clean:                         ## remove build artifacts
	rm -rf build __pycache__

help:                          ## list targets
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

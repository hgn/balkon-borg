# Enclosure (CadQuery). `make all` cleans, then rebuilds STEP + STL into build/.
PY := ../.venv/bin/python

.PHONY: all clean
all: clean                     ## clean then build the enclosure halves (STEP + STL)
	$(PY) balkon_borg.py

clean:                         ## remove build artifacts
	rm -rf build __pycache__

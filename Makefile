# Balkon-Borg — top-level build entry point. Run `make help` for targets.
# Everything is generated from source: `make all` builds, `make clean` cleans.
.DELETE_ON_ERROR:

.PHONY: all cad pcb firmware render preview clean distclean help

all: cad pcb firmware          ## build enclosure + board outputs + check firmware

cad:                           ## build the enclosure STEP/STL (cad/)
	$(MAKE) -C cad all

pcb:                           ## board fabrication outputs (pcb/)
	$(MAKE) -C pcb all

firmware:                      ## validate the ESPHome config (src/esp/)
	$(MAKE) -C src/esp all

render: cad                    ## render preview images + publish STL into docs/img/
	@mkdir -p docs/img
	f3d cad/build/balkon-borg-body.stl --output docs/img/enclosure.png \
	    --resolution 1400,900 --up +Z --camera-direction=-1,-0.6,0.4 \
	    --ambient-occlusion --anti-aliasing --background-color 0.1,0.1,0.12
	cp cad/build/balkon-borg-body.stl docs/img/enclosure.stl
	kicad-cli pcb render pcb/balkon-borg-carrier.kicad_pcb \
	    -o docs/img/pcb-top.png --side top --background opaque --quality high

preview: all render            ## build everything, then print how to view it
	@echo
	@echo 'View the rendered images:   feh -F **/*.png'
	@echo 'View a part in 3D:          f3d --up=+Z cad/build/balkon-borg-body.stl'
	@echo

clean:                         ## remove all build artifacts
	$(MAKE) -C cad clean
	$(MAKE) -C pcb clean
	$(MAKE) -C src/esp clean

distclean: clean               ## also remove the Python venv
	rm -rf .venv

help:                          ## list targets
	@grep -hE '^[a-zA-Z_-]+:.*?##' $(firstword $(MAKEFILE_LIST)) \
	    | awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

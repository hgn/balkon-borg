# ESPHome front-panel firmware. `make check` does a YAML sanity check; full
# validation and flashing use `esphome config/run balkon-borg.yaml`.
PY := ../../.venv/bin/python

.PHONY: all check clean
all: check                     ## validate the config

check:                         ## YAML sanity check (unknown ESPHome tags ignored)
	@$(PY) -c "import yaml; yaml.SafeLoader.add_multi_constructor('!', lambda l,t,n: None); yaml.load(open('balkon-borg.yaml'), Loader=yaml.SafeLoader); print('balkon-borg.yaml: OK')"

clean:                         ## remove the ESPHome build cache
	rm -rf .esphome __pycache__

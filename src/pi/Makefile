# borg-pi5 software. Provisioning and deployment run from here against the Pi; the
# repo is the source of truth and the Pi is a target host (there is no git on it).

.DELETE_ON_ERROR:
.DEFAULT_GOAL := help

HOST  ?= borg-pi
USER  ?= pfeifer
TARGET := $(USER)@$(HOST)
REMOTE := /srv/borg/app

PYTHON := python3

.PHONY: all check test types provision plan report deploy logs status shell clean distclean help

all: check ## what CI would do: types + tests

check: types test ## mypy strict + pytest

types: ## static type check (mypy strict)
	$(PYTHON) -m mypy --strict provision.py tests

test: ## run the test suite
	$(PYTHON) -m pytest -q

provision: ## bring the Pi to the target state (idempotent)
	./provision.py --host $(HOST) --user $(USER)

plan: ## show what provisioning would do, changing nothing
	./provision.py --host $(HOST) --user $(USER) --dry-run

report: ## read-only: what hardware the Pi currently sees
	./provision.py --host $(HOST) --user $(USER) --report

deploy: ## rsync the arbiter to the Pi and restart it
	rsync -a --delete --exclude '__pycache__' --exclude 'tests' \
		arbiter/ $(TARGET):$(REMOTE)/arbiter/
	rsync -a ../shared/ $(TARGET):$(REMOTE)/shared/
	ssh $(TARGET) 'systemctl --user restart borg-arbiter || true'

logs: ## follow the arbiter's log
	ssh $(TARGET) 'journalctl --user -u borg-arbiter -f'

status: ## unit and container status at a glance
	ssh $(TARGET) 'systemctl --user status borg-arbiter --no-pager; podman ps'

shell: ## open a shell on the Pi
	ssh $(TARGET)

clean: ## remove caches and build leftovers
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
	rm -rf .mypy_cache .pytest_cache

distclean: clean ## fresh-checkout state

help: ## list available targets
	@grep -E '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) | \
		awk -F':.*## ' '{printf "  %-11s %s\n", $$1, $$2}'

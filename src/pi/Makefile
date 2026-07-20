# borg-pi5 software. Provisioning and deployment run from here against the Pi; the
# repo is the source of truth and the Pi is a target host (there is no git on it).

.DELETE_ON_ERROR:
.DEFAULT_GOAL := help

HOST  ?= borg-pi
USER  ?= pfeifer
TARGET := $(USER)@$(HOST)
REMOTE := /srv/borg/app

PYTHON := python3

# The arbiter is a single static binary, cross-compiled for the Pi from here. The
# version is stamped in so the status page can say which tree is running.
ARBITER := arbiter/borg-arbiter
VERSION := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
GOFLAGS := -trimpath -ldflags "-s -w -X main.version=r$(VERSION)+$(COMMIT)"

.PHONY: all check test types build fmt provision plan report deploy logs status shell clean distclean help

all: check build ## what CI would do: checks, then the binary

check: types test ## mypy strict + go vet + both test suites

types: ## static checks (mypy strict for the tool, go vet for the arbiter)
	$(PYTHON) -m mypy --strict provision.py tests
	cd arbiter && go vet ./...

test: ## run both test suites
	$(PYTHON) -m pytest -q
	cd arbiter && go test ./...

build: ## cross-compile the arbiter for the Pi (linux/arm64)
	cd arbiter && GOOS=linux GOARCH=arm64 go build $(GOFLAGS) -o borg-arbiter .
	@ls -lh $(ARBITER) | awk '{print "  " $$9 ": " $$5}'

fmt: ## format the Go sources
	cd arbiter && gofmt -w *.go

provision: ## bring the Pi to the target state (idempotent)
	./provision.py --host $(HOST) --user $(USER)

plan: ## show what provisioning would do, changing nothing
	./provision.py --host $(HOST) --user $(USER) --dry-run

report: ## read-only: what hardware the Pi currently sees
	./provision.py --host $(HOST) --user $(USER) --report

deploy: build ## push the arbiter binary and the shared config, then restart it
	ssh $(TARGET) 'mkdir -p $(REMOTE)/shared'
	rsync -a $(ARBITER) $(TARGET):$(REMOTE)/borg-arbiter
	rsync -a ../shared/borg.yaml $(TARGET):$(REMOTE)/shared/borg.yaml
	ssh $(TARGET) 'systemctl --user restart borg-arbiter'
	@echo "deployed r$(VERSION)+$(COMMIT)"

logs: ## follow the arbiter's log
	ssh $(TARGET) 'journalctl --user -u borg-arbiter -f'

status: ## unit and container status at a glance
	ssh $(TARGET) 'systemctl --user status borg-arbiter --no-pager; podman ps'

shell: ## open a shell on the Pi
	ssh $(TARGET)

clean: ## remove caches and build leftovers
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
	rm -rf .mypy_cache .pytest_cache
	rm -f $(ARBITER)

distclean: clean ## fresh-checkout state

help: ## list available targets
	@grep -E '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) | \
		awk -F':.*## ' '{printf "  %-11s %s\n", $$1, $$2}'

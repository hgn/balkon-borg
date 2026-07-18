# Balkon-Borg Android app. The local toolchain (Java, SDK, Flutter) lives in
# env/ and is activated via env.sh; every target runs through it.

.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

FLUTTER := bash -c 'source $(CURDIR)/env.sh && cd $(CURDIR)/app && flutter $$0 $$@'
APK     := app/build/app/outputs/flutter-apk/app-release.apk

.PHONY: all apk check test analyze run clean distclean help

all: apk ## build the release APK

apk: ## build the release APK
	$(FLUTTER) build apk --release

check: analyze test ## analyze + tests

analyze: ## static analysis (flutter analyze)
	$(FLUTTER) analyze

test: ## run the test suite
	$(FLUTTER) test

run: ## run on a connected device (USB debugging)
	$(FLUTTER) run

clean: ## remove build artifacts
	$(FLUTTER) clean

distclean: clean ## fresh-checkout state (keeps the env/ toolchain)

help: ## list available targets
	@grep -E '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) | \
		awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

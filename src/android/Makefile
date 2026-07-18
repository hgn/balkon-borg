# Balkon-Borg Android app. The local toolchain (Java, SDK, Flutter) lives in
# env/ and is activated via env.sh; every target runs through it.

.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

FLUTTER := bash -c 'source $(CURDIR)/env.sh && cd $(CURDIR)/app && flutter $$0 $$@'
APK     := app/build/app/outputs/flutter-apk/app-release.apk
NAS_APK := /mnt/nas/borg.apk

.PHONY: all apk install sounds check test analyze run clean distclean help

sounds: ## regenerate the UI sound set (app/assets/audio/ui/)
	./gen-sounds.py

all: apk ## build the release APK

apk: ## build the release APK
	$(FLUTTER) build apk --release

install: apk ## build and copy the APK to the NAS share (run outside the sandbox)
	cp -a $(APK) $(NAS_APK)
	@echo "APK -> $(NAS_APK)"

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

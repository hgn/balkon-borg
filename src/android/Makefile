# Balkon-Borg Android app. The local toolchain (Java, SDK, Flutter) lives in
# env/ and is activated via env.sh; every target runs through it.

.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

FLUTTER := bash -c 'source $(CURDIR)/env.sh && cd $(CURDIR)/app && flutter $$0 $$@'
APK     := app/build/app/outputs/flutter-apk/app-release.apk
NAS_APK := /mnt/nas/borg.apk

# Build identity. The commit count is strictly increasing, so a phone showing
# a higher rNNN in the settings is running the newer APK, no guessing. It is
# also the Android versionCode, so an older APK cannot install over a newer
# one by accident.
REVISION := $(shell git rev-list --count HEAD)
COMMIT   := $(shell git rev-parse --short HEAD)
DATE     := $(shell git log -1 --date=format:%Y-%m-%d --format=%cd)
DIRTY    := $(shell git diff --quiet HEAD || echo true)

VERSION_FLAGS := \
	--build-name=0.1.$(REVISION) --build-number=$(REVISION) \
	--dart-define=BORG_REVISION=$(REVISION) \
	--dart-define=BORG_COMMIT=$(COMMIT) \
	--dart-define=BORG_DATE=$(DATE) \
	--dart-define=BORG_DIRTY=$(if $(DIRTY),true,false)

.PHONY: all apk install sounds check test analyze run version clean distclean help

sounds: ## regenerate the UI sound set (app/assets/audio/generated-sounds/)
	./gen-sounds.py --out app/assets/audio/generated-sounds

all: apk ## build the release APK

apk: ## build the release APK
	$(FLUTTER) build apk --release $(VERSION_FLAGS)

install: apk ## build and copy the APK to the NAS share
	cp -a $(APK) $(NAS_APK)
	@echo "APK -> $(NAS_APK)  (r$(REVISION), $(DATE), $(COMMIT))"

version: ## show the build identity this tree would produce
	@echo "r$(REVISION)$(if $(DIRTY),+) $(DATE) $(COMMIT)"

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

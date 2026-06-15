PROJECT       := hark
SCHEME        := hark
CONFIGURATION ?= Debug
DERIVED_DATA  := build

.DEFAULT_GOAL := build

.PHONY: generate build run open clean

generate:
	@command -v xcodegen >/dev/null 2>&1 || { printf 'xcodegen not found; install with: brew install xcodegen\n' >&2; exit 1; }
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) build

run: build
	open $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(PROJECT).app

open: generate
	open $(PROJECT).xcodeproj

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT).xcodeproj

PROJECT       := hark
SCHEME        := hark
CONFIGURATION ?= Debug
DERIVED_DATA  := build

.DEFAULT_GOAL := build

.PHONY: generate build test run open lint format clean

generate:
	@command -v xcodegen >/dev/null 2>&1 || { printf 'xcodegen not found; install with: brew install xcodegen\n' >&2; exit 1; }
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) build

test: generate
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) test

run: build
	open $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(PROJECT).app

open: generate
	open $(PROJECT).xcodeproj

lint:
	@command -v swiftformat >/dev/null 2>&1 || { printf 'swiftformat not found; install with: brew install swiftformat\n' >&2; exit 1; }
	@command -v swiftlint >/dev/null 2>&1 || { printf 'swiftlint not found; install with: brew install swiftlint\n' >&2; exit 1; }
	swiftformat --lint .
	swiftlint lint --strict

format:
	@command -v swiftformat >/dev/null 2>&1 || { printf 'swiftformat not found; install with: brew install swiftformat\n' >&2; exit 1; }
	swiftformat .

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT).xcodeproj

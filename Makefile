PROJECT       := hark
SCHEME        := hark
CONFIGURATION ?= Debug
VERSION       ?=
DERIVED_DATA  := build
XCODE_DERIVED := $(HOME)/Library/Developer/Xcode/DerivedData

.DEFAULT_GOAL := build

.PHONY: generate build test run open lint format clean

generate:
	@command -v xcodegen >/dev/null 2>&1 || { printf 'xcodegen not found; install with: brew install xcodegen\n' >&2; exit 1; }
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) $(if $(VERSION),MARKETING_VERSION=$(VERSION)) build

test: generate
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) test

run: build
	$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(PROJECT).app/Contents/MacOS/$(PROJECT)

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

# Also clear Xcode's own DerivedData for this project; a stale build there keeps
# serving a blank app icon to the Dock even after a rebuild.
clean:
	rm -rf $(DERIVED_DATA) $(PROJECT).xcodeproj
	rm -rf $(XCODE_DERIVED)/$(PROJECT)-*

# Hark

A minimal SwiftUI macOS app for recording meetings.

## Requirements

- macOS 26 or later
- Xcode 26 (provides the macOS 26 SDK and `xcodebuild`)
- XcodeGen, SwiftFormat, SwiftLint (`brew install xcodegen swiftformat swiftlint`)

## Build

The Xcode project is generated from `project.yml` and is not checked in. Generate it and build:

```sh
make build
```

To open the generated project in Xcode:

```sh
make open
```

## Run

```sh
make run
```

On first launch, grant microphone access when prompted. Recordings are written as timestamped `.m4a` files in the app's Documents container.

## Test

```sh
make test
```

Tests use the Swift Testing framework and live in `Tests/`.

## Lint and Format

```sh
make lint     # check formatting and run SwiftLint
make format   # apply SwiftFormat in place
```

## Continuous Integration

Pull requests run `lint.yml` (SwiftFormat and SwiftLint) and `test.yml` (build and test) on a `macos-26` runner, and `pre-release.yml` enforces a Conventional Commits pull request title.

Merging to `main` runs `release.yml`. It first computes the next version from the Conventional Commit history with a semantic-release dry run. If a release is warranted, it builds the `Release` configuration with that version stamped into the app, and only then does `create-github-release` cut the tag and GitHub Release, to which the zipped app is attached. Building before the release is cut means a failed build never leaves a version-bumped release without its artifact. The attached `hark.zip` is unsigned and intended for distribution via a Homebrew cask (maintained separately), which clears Gatekeeper quarantine on install. Dependabot keeps the pinned actions current.

## Layout

- `project.yml`: XcodeGen project specification
- `Sources/`: app entry point, view, and the microphone recorder
- `Tests/`: Swift Testing unit tests
- `Resources/Info.plist`: app metadata and the microphone usage string
- `hark.entitlements`: app sandbox and microphone entitlement
- `.swiftformat`, `.swiftlint.yml`: formatter and linter configuration
- `.github/`: lint, test, and release workflows, Dependabot, and code owners
- `Makefile`: generate, build, test, run, lint, format, and clean targets

## Status

v0.0.1 records microphone audio only. Capturing system audio (the other meeting participants) is planned.

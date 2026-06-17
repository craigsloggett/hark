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

On first launch, grant microphone access when prompted. The first recording also prompts for system audio access (shown as the purple recording indicator, not screen recording). Each recording creates a timestamped `hark-<timestamp>/` folder in the app's Documents container holding `mic.wav` (your microphone) and `system.wav` (everything you hear).

For clean system audio, use a non-Bluetooth microphone. The tap captures only what the output device renders, so using a Bluetooth headset as both the microphone and the output switches it into the low-quality HFP call mode, which starves the system audio capture.

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

## Layout

- `project.yml`: XcodeGen project specification
- `Sources/`: app entry point, view, the dual-stream recorder, and the Core Audio system audio tap
- `Tests/`: Swift Testing unit tests
- `Resources/Info.plist`: app metadata and the microphone and system audio usage strings
- `hark.entitlements`: app sandbox and audio input entitlement
- `.swiftformat`, `.swiftlint.yml`: formatter and linter configuration
- `Makefile`: generate, build, test, run, lint, format, and clean targets

## Status

Hark records your microphone and the system audio you hear as two synchronized files per session, using a Core Audio process tap for system audio. Producing a diarized transcription from these recordings is planned.

# Hark

A minimal SwiftUI macOS app for recording meetings.

## Requirements

- macOS 26 or later
- Xcode 26 (provides the macOS 26 SDK and `xcodebuild`)
- XcodeGen (`brew install xcodegen`)

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

## Layout

- `project.yml`: XcodeGen project specification
- `Sources/`: app entry point, view, and the microphone recorder
- `Resources/Info.plist`: app metadata and the microphone usage string
- `hark.entitlements`: app sandbox and microphone entitlement
- `Makefile`: generate, build, run, and clean targets

## Status

v0.0.1 records microphone audio only. Capturing system audio (the other meeting participants) is planned.

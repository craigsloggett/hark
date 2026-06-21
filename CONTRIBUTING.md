# Contributing to Hark

Hark is a SwiftUI macOS app. The Xcode project is generated from `project.yml`, and common tasks run through the Makefile.

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

On first launch, grant microphone access when prompted. The first recording also prompts for system audio access (shown as the purple recording indicator, not screen recording). Each recording creates a timestamped `hark-<timestamp>/` folder in the app's Documents container holding `mic.wav` (your microphone) and `system.wav` (everything you hear), both 16 kHz mono.

After a recording, click Transcribe to transcribe that session. Transcription runs on-device with Apple's `SpeechAnalyzer`, and the system-audio track is diarized into individual remote speakers on-device with [FluidAudio](https://github.com/FluidInference/FluidAudio). The first run downloads the speech model and the diarization models (needs network once) and prompts for speech recognition access. It writes `transcript.txt` and `transcript.json` into the session folder, merging both tracks into one timeline: your microphone is You, and each remote participant is Speaker 1, Speaker 2, and so on. The `transcript.json` `speaker` field is `you`, `speaker1`, `speaker2`, and so on.

To inspect diarization segmentation, enable `HARK_DIARIZATION_DEBUG`. It is pre-declared but unchecked in the scheme (turn it on in Edit Scheme → Run → Arguments → Environment Variables), or run from the shell with `HARK_DIARIZATION_DEBUG=1 make run`. When set, transcription writes `diarization.debug.json` into the session folder with the raw segments (start, end, speaker, activity).

System audio is captured with a private, tap-only aggregate device. Recording stays full-duration and correct-speed regardless of the output device or its sample-rate changes, including a Bluetooth headset in HFP call mode (the same headset used as both microphone and output). The tap captures the system mix independent of the output device's link rate, and every buffer is resampled to the canonical 16 kHz.

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
- `Sources/`: app entry point, view, the dual-stream recorder, the Core Audio system audio tap, on-device transcription, and speaker diarization
- `Tests/`: Swift Testing unit tests
- `Resources/Info.plist`: app metadata and the microphone, system audio, and speech recognition usage strings
- `hark.entitlements`: app sandbox, audio input, and network client (for the first-run transcription and diarization model downloads) entitlements
- `.swiftformat`, `.swiftlint.yml`: formatter and linter configuration
- `Makefile`: generate, build, test, run, lint, format, and clean targets

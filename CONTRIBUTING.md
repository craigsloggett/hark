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

After a recording, click Transcribe to transcribe that session. Transcription and diarization both run on-device with [FluidAudio](https://github.com/FluidInference/FluidAudio): the [Parakeet TDT v3](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) model transcribes each track, and the system-audio track is diarized into individual remote speakers. The first run downloads the transcription and diarization models (needs network once). It writes `transcript.txt` and `transcript.json` into the session folder, merging both tracks into one timeline: your microphone is You, and each remote participant is Speaker 1, Speaker 2, and so on. The `transcript.json` `speaker` field is `you`, `speaker1`, `speaker2`, and so on.

Utterances come from a token-timing interval join, not the model's sentence segmentation: each track is transcribed in one pass into per-token timings, the system track's tokens are tagged with the diarized speaker their midpoint falls in, and consecutive tokens are grouped into utterances, breaking on a speaker change or a silence gap. Punctuation rides along with the word it follows and subword pieces stay with their word, so neither splits an utterance. Override the gap (default 0.4s) with `HARK_UTTERANCE_GAP_MS` to tune segmentation on real meetings.

To inspect the raw segments, enable `HARK_DIARIZATION_DEBUG` or `HARK_ASR_DEBUG`. Both are pre-declared but unchecked in the scheme (turn them on in Edit Scheme → Run → Arguments → Environment Variables), or run from the shell with `HARK_DIARIZATION_DEBUG=1 make run`. When set, transcription writes `diarization.debug.json` (raw diarization segments: start, end, speaker, quality) and `asr.<track>.debug.json` (raw tokens: start, end, text) into the session folder.

Diarization runs FluidAudio's offline pyannote community-1 pipeline. Four accuracy knobs override its defaults from the environment, each falling back to the default when unset: `HARK_DIARIZATION_CLUSTER_THRESHOLD` (default 0.75; on this VBx pipeline higher yields more speakers up to ~0.9 then collapses, the inverse of plain AHC, and community-1's stock 0.6 under-clusters hark's mixed remote-meeting audio), `HARK_DIARIZATION_FA` (VBx precision warm-start, default 0.13, raised from community's 0.07; below ~0.125 close-voiced remote speakers merge into the dominant cluster, above ~0.135 the dominant speaker's own quieter passages fragment into phantom speakers, so 0.13 centres the narrow band that does neither), `HARK_DIARIZATION_MIN_SEGMENT_MS` (default 1000; lower lets brief turns get their own speaker embedding), and `HARK_DIARIZATION_STEP_RATIO` (default 0.2; lower sharpens turn boundaries at roughly 2x cost). The active values are logged in the per-run "Diarized …" summary. To sweep them on a saved session without re-recording, write a `.hark-fixture` file naming the session folder into the container's Documents directory, then run the knob plus `make test`, for example `HARK_DIARIZATION_CLUSTER_THRESHOLD=0.5 make test`. `TranscriptionFixtureTests` re-transcribes that session to `transcript.parakeet.txt`, leaving any reference `transcript.txt` untouched.

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
- `Resources/Info.plist`: app metadata and the microphone and system audio usage strings
- `hark.entitlements`: app sandbox, audio input, and network client (for the first-run transcription and diarization model downloads) entitlements
- `.swiftformat`, `.swiftlint.yml`: formatter and linter configuration
- `Makefile`: generate, build, test, run, lint, format, and clean targets

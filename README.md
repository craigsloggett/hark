<p align="center">
  <img src="Assets/AppIcon.png" width="128" height="128" alt="Hark app icon">
</p>

<h1 align="center">Hark</h1>

Hark is an app that produces personal meeting transcriptions with diarization for offline note-taking. There is no subscription, no cloud service, nothing leaves your device.

The goal is a simple utility that just works and feels delightful. Start transcribing with a key stroke, and get a transcript you can actually read. You are labeled You, and each other participant becomes Speaker 1, Speaker 2, and so on. Hark allows you to customize speaker labels and can automatically detect speakers over time, automatically applying your custom label in future transcripts.

- Able to capture any meeting, regardless of the application you are meeting in.
- Transcribes and separates speakers on-device into one merged timeline.
- Stays fully local and private, with no cloud services in the loop.

## Requirements

Hark runs on macOS 26 or later.

## Contributing

Hark is a SwiftUI app. The Xcode project is generated from `project.yml` with XcodeGen, and common tasks run through the Makefile. Install the toolchain with `brew install xcodegen swiftformat swiftlint` and build with Xcode 26.

```sh
make build   # generate the project and build
make run     # build and launch
make test    # run the unit tests
make lint    # check formatting and SwiftLint
```

Application code lives in `Sources/` and tests in `Tests/`. Transcription and speaker diarization run on-device through [FluidAudio](https://github.com/FluidInference/FluidAudio), and its models download on first transcribe. See [CONTRIBUTING.md](CONTRIBUTING.md) for the recording, transcription, and diarization internals.

import Foundation
@testable import hark
import Testing

/// Offline A/B harness: re-transcribes saved recording sessions under a one-factor-at-a-time sweep of
/// the per-recording diarization and transcription preferences, writing metrics and per-run
/// transcripts to `Documents/.hark-sweep-out` for comparison. Each knob lists only its deltas from the
/// shipped defaults; a single baseline run per session supplies the default point for every series.
///
/// Disabled unless a `.hark-sweep` marker in the container's Documents lists the sessions to process,
/// so it never runs in CI. The user's preferences and voiceprint DB are restored when it finishes.
struct TuningSweepTests {
    /// One sweep value, type-tagged so it writes back through the matching `UserDefaults` setter.
    private enum KnobValue: CustomStringConvertible {
        case double(Double)
        case bool(Bool)
        case int(Int)

        func store(_ key: String, in defaults: UserDefaults) {
            switch self {
            case let .double(value): defaults.set(value, forKey: key)
            case let .bool(value): defaults.set(value, forKey: key)
            case let .int(value): defaults.set(value, forKey: key)
            }
        }

        var description: String {
            switch self {
            case let .double(value): String(value)
            case let .bool(value): String(value)
            case let .int(value): String(value)
            }
        }
    }

    private struct Knob {
        let name: String
        let key: String
        /// Non-default values only; the baseline run covers the shipped default.
        let values: [KnobValue]
    }

    private struct Target {
        let url: URL
        /// Knob names to sweep for this session, or `nil` to sweep them all.
        let knobs: Set<String>?
    }

    // MARK: Configuration

    private static var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Marker lines `"<session-folder>[ knob,knob,...]"`; an absent or empty marker skips the test.
    private static var targets: [Target] {
        guard let documents,
              let raw = try? String(contentsOf: documents.appendingPathComponent(".hark-sweep"), encoding: .utf8)
        else { return [] }
        return raw.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let name = parts.first.map(String.init), !name.isEmpty else { return nil }
            let knobs = parts.count > 1
                ? Set(parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                : nil
            return Target(url: documents.appendingPathComponent(name, isDirectory: true), knobs: knobs)
        }
    }

    /// One-factor-at-a-time deltas from the shipped defaults. Every value stays within
    /// `OfflineDiarizerConfig.validate()` bounds (pinned by `FluidAudioContractTests`).
    private static let matrix: [Knob] = [
        Knob(name: "clustering", key: Preferences.Key.diarizationClusteringThreshold,
             values: [.double(0.55), .double(0.65), .double(0.85), .double(0.95)]),
        Knob(name: "Fa", key: Preferences.Key.diarizationSpeakerSensitivity,
             values: [.double(0.07), .double(0.25)]),
        Knob(name: "Fb", key: Preferences.Key.diarizationSpeakerRecall,
             values: [.double(0.5), .double(1.2)]),
        Knob(name: "stepRatio", key: Preferences.Key.diarizationStepRatio,
             values: [.double(0.1), .double(0.5)]),
        Knob(name: "minSeg", key: Preferences.Key.diarizationMinSegmentDuration,
             values: [.double(1.0), .double(3.0)]),
        Knob(name: "minGap", key: Preferences.Key.diarizationMinGapDuration,
             values: [.double(0.0), .double(0.5)]),
        Knob(name: "exclusive", key: Preferences.Key.diarizationExclusiveSegments,
             values: [.bool(false)]),
        Knob(name: "maxSpeakers", key: Preferences.Key.diarizationMaxSpeakers,
             values: [.int(4), .int(6), .int(8)]),
        Knob(name: "uttGap", key: Preferences.Key.utteranceGap,
             values: [.double(0.2), .double(0.8)]),
    ]

    private static let header =
        "session\tknob\tvalue\telapsed_s\tsegments\tspeakers_total\tspeakers_remote\twords\tper_speaker"

    // MARK: Sweep

    @Test(.enabled(if: !TuningSweepTests.targets.isEmpty))
    func runSweep() async throws {
        let docs = try #require(Self.documents)
        let outDir = docs.appendingPathComponent(".hark-sweep-out", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let resultsURL = outDir.appendingPathComponent("results.tsv")

        let defaults = UserDefaults.standard
        let prefSnapshot = Self.snapshot(defaults)
        let voiceprints = try Self.voiceprintsURL()
        let voiceprintSnapshot = try? Data(contentsOf: voiceprints)
        defer {
            Self.restore(prefSnapshot, to: defaults)
            Self.resetVoiceprints(voiceprintSnapshot, at: voiceprints)
        }

        // Reuse one service so models load once, then stay cached on the Transcriber/Diarizer actors.
        let service = TranscriptionService()
        var rows = [Self.header]

        func run(_ target: Target, _ knob: String, _ value: String, override: (UserDefaults) -> Void) async {
            Self.applyDefaults(defaults)
            override(defaults)
            Self.resetVoiceprints(voiceprintSnapshot, at: voiceprints)
            do {
                let start = Date()
                let transcript = try await service.transcribeSession(at: target.url).transcript
                let elapsed = Date().timeIntervalSince(start)
                rows.append(Self.metricsRow(target.url, knob, value, elapsed, transcript))
                let stem = "\(target.url.lastPathComponent)__\(knob)__\(value)"
                try? transcript.segments.writeJSON(to: outDir.appendingPathComponent("\(stem).json"))
            } catch {
                rows.append([
                    target.url.lastPathComponent, knob, value, "ERROR", "-", "-", "-", "-",
                    String(describing: error),
                ].joined(separator: "\t"))
            }
            // Rewrite after each run so a crash still leaves a complete partial file.
            try? (rows.joined(separator: "\n") + "\n").write(to: resultsURL, atomically: true, encoding: .utf8)
        }

        for target in Self.targets {
            await run(target, "baseline", "default") { _ in }
            for knob in Self.matrix where target.knobs?.contains(knob.name) ?? true {
                for value in knob.values {
                    await run(target, knob.name, value.description) { value.store(knob.key, in: $0) }
                }
            }
        }
    }

    // MARK: Metrics

    private static func metricsRow(
        _ session: URL,
        _ knob: String,
        _ value: String,
        _ elapsed: TimeInterval,
        _ transcript: Transcript
    ) -> String {
        let segments = transcript.segments
        let words = segments.reduce(0) { $0 + wordCount($1.text) }
        let speakersTotal = Set(segments.map(\.speaker.label)).count
        let speakersRemote = Set(segments.compactMap { segment -> Int? in
            if case let .remote(index) = segment.speaker { index } else { nil }
        }).count
        var perSpeaker: [String: Int] = [:]
        for segment in segments {
            perSpeaker[segment.speaker.label, default: 0] += wordCount(segment.text)
        }
        let distribution = perSpeaker.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return [
            session.lastPathComponent, knob, value, String(Int(elapsed.rounded())),
            String(segments.count), String(speakersTotal), String(speakersRemote), String(words), distribution,
        ].joined(separator: "\t")
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    // MARK: Preference + voiceprint state

    private static let allKeys = [
        Preferences.Key.diarizationClusteringThreshold, Preferences.Key.diarizationSpeakerSensitivity,
        Preferences.Key.diarizationSpeakerRecall, Preferences.Key.diarizationStepRatio,
        Preferences.Key.diarizationMinSegmentDuration, Preferences.Key.diarizationMinGapDuration,
        Preferences.Key.diarizationExclusiveSegments, Preferences.Key.diarizationMaxSpeakers,
        Preferences.Key.speakerMatchThreshold, Preferences.Key.speakerMinEnrollmentDuration,
        Preferences.Key.voiceprintMaxSamples, Preferences.Key.asrDualDecodeArbitration,
        Preferences.Key.asrParallelChunkConcurrency, Preferences.Key.utteranceGap,
    ]

    private static func snapshot(_ defaults: UserDefaults) -> [String: Any] {
        // The persistent domain excludes registration defaults, so we capture only the user's explicit
        // settings and never persist a registered default back as if the user had chosen it.
        let domain = Bundle.main.bundleIdentifier ?? ""
        let persisted = defaults.persistentDomain(forName: domain) ?? [:]
        return persisted.filter { allKeys.contains($0.key) }
    }

    private static func restore(_ snapshot: [String: Any], to defaults: UserDefaults) {
        for key in allKeys {
            if let value = snapshot[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// The knobs this sweep varies; clearing them lets `Preferences` fall back to its shipped default.
    private static let sweptKeys = [
        Preferences.Key.diarizationClusteringThreshold,
        Preferences.Key.diarizationSpeakerSensitivity,
        Preferences.Key.diarizationSpeakerRecall,
        Preferences.Key.diarizationStepRatio,
        Preferences.Key.diarizationMinSegmentDuration,
        Preferences.Key.diarizationMinGapDuration,
        Preferences.Key.diarizationExclusiveSegments,
        Preferences.Key.diarizationMaxSpeakers,
        Preferences.Key.utteranceGap,
    ]

    /// Clears every swept knob so each run reverts to the shipped defaults before overriding one factor.
    private static func applyDefaults(_ defaults: UserDefaults) {
        for key in sweptKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private static func voiceprintsURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Hark/voiceprints.json")
    }

    /// Restores the voiceprint DB to its pre-sweep bytes (or removes it when there were none) so
    /// enrollment side effects don't accumulate across runs.
    private static func resetVoiceprints(_ snapshot: Data?, at url: URL) {
        if let snapshot {
            try? snapshot.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

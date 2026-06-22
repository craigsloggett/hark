import FluidAudio
import Foundation
import OSLog

/// Diarizes the system-audio track into speaker turns with FluidAudio's on-device offline
/// pyannote-community-1 pipeline. The CoreML models load once and are cached on this actor; each
/// call drives them through a short-lived, non-`Sendable` manager that never leaves the actor.
actor Diarizer {
    private let logger = Logger(subsystem: "com.craigsloggett.hark", category: "Diarizer")

    private var models: OfflineDiarizerModels?

    /// FluidAudio's community-1 defaults, with optional `HARK_DIARIZATION_*` overrides applied so
    /// accuracy can be swept on saved recordings without a rebuild.
    private let config = Diarizer.configFromEnvironment()

    /// Diarizes a 16 kHz mono recording into turns sorted by start time. The offline pipeline's
    /// default exclusive segments mean turns do not overlap.
    /// - Returns: the speaker turns, or an empty array when the track is silent.
    func turns(in fileURL: URL) async throws -> [DiarizationTurn] {
        let manager = OfflineDiarizerManager(config: config)
        try await manager.initialize(models: loadedModels())

        let result: DiarizationResult
        do {
            result = try await manager.process(fileURL)
        } catch OfflineDiarizationError.noSpeechDetected {
            // The offline pipeline throws on silence; mirror the upstream track-level guard so a
            // near-silent system track collapses to Speaker 1 rather than surfacing an error.
            return []
        } catch {
            throw TranscriptionError.diarizationFailed(String(describing: error))
        }

        // Offline output groups by speaker, so order it before reporting and mapping.
        let segments = result.segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }
        report(segments, for: fileURL)

        guard !segments.isEmpty else {
            logger.warning("No speech in \(fileURL.lastPathComponent, privacy: .public); remote collapses to Speaker 1")
            return []
        }
        return segments.map {
            DiarizationTurn(
                start: Double($0.startTimeSeconds),
                end: Double($0.endTimeSeconds),
                speakerId: $0.speakerId
            )
        }
    }

    /// Loads the offline diarizer models once and caches them. The result is `Sendable`, so a
    /// fresh per-call manager can reuse it without re-downloading.
    private func loadedModels() async throws -> OfflineDiarizerModels {
        if let models { return models }
        do {
            let loaded = try await OfflineDiarizerModels.load()
            models = loaded
            return loaded
        } catch {
            let reason = String(describing: error)
            throw TranscriptionError.diarizationFailed("couldn't load the diarization model: \(reason)")
        }
    }

    /// hark raises community-1's clustering threshold from 0.6 to 0.75. On this offline VBx pipeline
    /// a higher threshold yields *more* speakers (the opposite of plain AHC), and 0.6 collapses the
    /// distinct voices in hark's mixed remote-meeting audio into one. 0.75 is the centre of a wide
    /// stable plateau (~0.68-0.85) that separates them; below ~0.65 they merge, above ~0.9 they do too.
    private static let defaultClusterThreshold = 0.75

    /// Builds the offline config from FluidAudio's community-1 defaults, overriding individual knobs
    /// from `HARK_DIARIZATION_*` when set. Unset or unparseable values keep the default.
    private static func configFromEnvironment() -> OfflineDiarizerConfig {
        let env = ProcessInfo.processInfo.environment
        return OfflineDiarizerConfig(
            clusteringThreshold: double(env, "HARK_DIARIZATION_CLUSTER_THRESHOLD")
                ?? defaultClusterThreshold,
            segmentationStepRatio: double(env, "HARK_DIARIZATION_STEP_RATIO")
                ?? OfflineDiarizerConfig.Segmentation.community.stepRatio,
            minSegmentDuration: seconds(env, "HARK_DIARIZATION_MIN_SEGMENT_MS")
                ?? OfflineDiarizerConfig.Embedding.community.minSegmentDurationSeconds
        )
    }

    private static func double(_ env: [String: String], _ key: String) -> Double? {
        guard let raw = env[key], let value = Double(raw) else { return nil }
        return value
    }

    /// Reads a millisecond-valued knob and returns it in seconds.
    private static func seconds(_ env: [String: String], _ key: String) -> Double? {
        guard let milliseconds = double(env, key) else { return nil }
        return milliseconds / 1000
    }

    /// Logs a summary of the result and, when `HARK_DIARIZATION_DEBUG` is set, writes the raw
    /// segments to `diarization.debug.json` next to the input.
    private func report(_ segments: [TimedSpeakerSegment], for fileURL: URL) {
        let speakers = Set(segments.map(\.speakerId)).count
        let speech = segments.reduce(Float(0)) { $0 + $1.durationSeconds }
        let qualities = segments.map(\.qualityScore)
        let avgQuality = qualities.isEmpty ? 0 : qualities.reduce(0, +) / Float(qualities.count)
        let summary = String(
            format: "%d turns, %d speakers, %.1fs speech, avg quality %.2f (threshold %.2f, step %.2f, minSeg %.2fs)",
            segments.count, speakers, speech, avgQuality,
            config.clusteringThreshold, config.segmentationStepRatio, config.minSegmentDuration
        )
        logger.log("Diarized \(fileURL.lastPathComponent, privacy: .public): \(summary, privacy: .public)")

        guard ProcessInfo.processInfo.environment["HARK_DIARIZATION_DEBUG"] != nil else { return }
        let dump = segments.map {
            DebugSegment(
                start: Double($0.startTimeSeconds),
                end: Double($0.endTimeSeconds),
                speaker: $0.speakerId,
                quality: Double($0.qualityScore)
            )
        }
        let debugURL = fileURL.deletingLastPathComponent().appendingPathComponent("diarization.debug.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dump).write(to: debugURL, options: .atomic)
        } catch {
            let reason = String(describing: error)
            logger.error("Couldn't write diarization debug dump: \(reason, privacy: .public)")
        }
    }

    /// One segment in the `HARK_DIARIZATION_DEBUG` dump.
    private struct DebugSegment: Encodable {
        let start: Double
        let end: Double
        let speaker: String
        let quality: Double
    }
}

import FluidAudio
import Foundation
import OSLog

/// Diarizes the system-audio track with FluidAudio's offline pyannote community-1 pipeline. The
/// models are `Sendable` and cached here; the manager is not, so a fresh one is built per call and
/// never leaves the actor.
actor Diarizer {
    private let logger = Logger(subsystem: "com.craigsloggett.hark", category: "Diarizer")

    private var models: OfflineDiarizerModels?
    private let config = Diarizer.configFromEnvironment()

    /// Diarizes a 16 kHz mono recording into speaker turns sorted by start time.
    /// - Returns: the turns, or an empty array when the track is silent.
    func turns(in fileURL: URL) async throws -> [DiarizationTurn] {
        let manager = OfflineDiarizerManager(config: config)
        try await manager.initialize(models: loadedModels())

        let result: DiarizationResult
        do {
            result = try await manager.process(fileURL)
        } catch OfflineDiarizationError.noSpeechDetected {
            // The pipeline throws on silence; treat it as an empty timeline rather than an error.
            return []
        } catch {
            throw TranscriptionError.diarizationFailed(String(describing: error))
        }

        // Offline output is grouped by speaker, not time, so sort before mapping.
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

    private func loadedModels() async throws -> OfflineDiarizerModels {
        if let models { return models }
        do {
            let loaded = try await OfflineDiarizerModels.load()
            models = loaded
            return loaded
        } catch {
            throw TranscriptionError.diarizationFailed("couldn't load the diarization model: \(error)")
        }
    }

    /// Community-1's stock 0.6 under-clusters hark's mixed remote-meeting audio; 0.75 separates the speakers.
    private static let defaultClusterThreshold = 0.75

    /// 0.13 separates close-voiced remote speakers without splitting the dominant speaker's quieter passages.
    private static let defaultFa = 0.13

    /// Builds the config from community-1 defaults, applying any `HARK_DIARIZATION_*` overrides.
    private static func configFromEnvironment() -> OfflineDiarizerConfig {
        let env = ProcessInfo.processInfo.environment
        return OfflineDiarizerConfig(
            clusteringThreshold: double(env, "HARK_DIARIZATION_CLUSTER_THRESHOLD")
                ?? defaultClusterThreshold,
            Fa: double(env, "HARK_DIARIZATION_FA") ?? defaultFa,
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

    private static func seconds(_ env: [String: String], _ key: String) -> Double? {
        guard let milliseconds = double(env, key) else { return nil }
        return milliseconds / 1000
    }

    /// Logs a summary and, when `HARK_DIARIZATION_DEBUG` is set, writes the raw segments to
    /// `diarization.debug.json` next to the input.
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
        let dump = segments.map(DebugSegment.init)
        let debugURL = fileURL.deletingLastPathComponent().appendingPathComponent("diarization.debug.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dump).write(to: debugURL, options: .atomic)
        } catch {
            logger.error("Couldn't write diarization debug dump: \(String(describing: error), privacy: .public)")
        }
    }

    /// One segment in the `HARK_DIARIZATION_DEBUG` dump.
    private struct DebugSegment: Encodable {
        let start: Double
        let end: Double
        let speaker: String
        let quality: Double

        init(_ segment: TimedSpeakerSegment) {
            start = Double(segment.startTimeSeconds)
            end = Double(segment.endTimeSeconds)
            speaker = segment.speakerId
            quality = Double(segment.qualityScore)
        }
    }
}

import FluidAudio
import Foundation
import OSLog

/// Diarizes the system-audio track with FluidAudio's offline pyannote community-1 pipeline.
actor Diarizer {
    private let logger = Logger(subsystem: "com.craigsloggett.hark", category: "Diarizer")

    private var models: OfflineDiarizerModels?
    private let config = Diarizer.configFromPreferences()

    /// Diarizes a 16 kHz mono recording into speaker turns sorted by start time.
    /// - Returns: the turns, or an empty array when the track is silent.
    func turns(in fileURL: URL) async throws -> [DiarizationTurn] {
        let manager = OfflineDiarizerManager(config: config)
        try await manager.initialize(models: loadedModels())

        let result: DiarizationResult
        do {
            result = try await manager.process(fileURL)
        } catch OfflineDiarizationError.noSpeechDetected {
            // Treat silence as an empty timeline rather than an error.
            return []
        } catch {
            throw TranscriptionError.diarizationFailed(String(describing: error))
        }

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

    private static func configFromPreferences() -> OfflineDiarizerConfig {
        OfflineDiarizerConfig(
            clusteringThreshold: Preferences.diarizationClusteringThreshold,
            Fa: Preferences.diarizationFa,
            segmentationStepRatio: Preferences.diarizationStepRatio,
            minSegmentDuration: Preferences.diarizationMinSegmentDuration
        )
    }

    /// Logs a one-line diarization summary.
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
        writeDebugDump(segments, for: fileURL)
    }

    // MARK: Debug

    /// When `HARK_DIARIZATION_DEBUG` is set, writes the raw segments to `diarization.debug.json`
    /// next to the input.
    private func writeDebugDump(_ segments: [TimedSpeakerSegment], for fileURL: URL) {
        guard ProcessInfo.processInfo.flag(forKey: "HARK_DIARIZATION_DEBUG") else { return }
        let dump = segments.map(DebugSegment.init)
        let debugURL = fileURL.deletingLastPathComponent().appendingPathComponent("diarization.debug.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dump).write(to: debugURL, options: .atomic)
        } catch {
            logger.error("Couldn't write diarization debug dump: \(error, privacy: .public)")
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

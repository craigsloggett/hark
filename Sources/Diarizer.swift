import FluidAudio
import Foundation
import OSLog

/// Diarizes the system-audio track into speaker turns with FluidAudio's on-device
/// LS-EEND model. The model is non-`Sendable`, so it lives behind this actor on a single
/// isolation domain.
actor Diarizer {
    private let logger = Logger(subsystem: "com.craigsloggett.hark", category: "Diarizer")

    private var model: LSEENDDiarizer?

    /// Diarizes a 16 kHz mono recording into turns sorted by start time. Turns may overlap
    /// when speakers talk at once.
    /// - Returns: the speaker turns, or an empty array when the track is silent.
    func turns(in fileURL: URL) async throws -> [DiarizationTurn] {
        let diarizer = try await loadedModel()
        let timeline: DiarizerTimeline
        do {
            // Each recording is a fresh session; don't carry speaker identities across files.
            timeline = try diarizer.processComplete(audioFileURL: fileURL, keepingEnrolledSpeakers: false)
        } catch {
            throw TranscriptionError.diarizationFailed(String(describing: error))
        }

        let segments = timeline.speakers.values
            .flatMap(\.finalizedSegments)
            .sorted { $0.startFrame < $1.startFrame }
        report(segments, for: fileURL)

        guard !segments.isEmpty else {
            logger.warning("No speech in \(fileURL.lastPathComponent, privacy: .public); remote collapses to Speaker 1")
            return []
        }
        return segments.map {
            DiarizationTurn(
                start: Double($0.startTime),
                end: Double($0.endTime),
                speakerId: String($0.speakerIndex)
            )
        }
    }

    private func loadedModel() async throws -> LSEENDDiarizer {
        if let model { return model }
        do {
            let loaded = try await LSEENDDiarizer(variant: .dihard3)
            model = loaded
            return loaded
        } catch {
            let reason = String(describing: error)
            throw TranscriptionError.diarizationFailed("couldn't load the diarization model: \(reason)")
        }
    }

    /// Logs a summary of the result and, when `HARK_DIARIZATION_DEBUG` is set, writes the raw
    /// segments to `diarization.debug.json` next to the input.
    private func report(_ segments: [DiarizerSegment], for fileURL: URL) {
        let speakers = Set(segments.map(\.speakerIndex)).count
        let speech = segments.reduce(Float(0)) { $0 + $1.duration }
        let activities = segments.map(\.activity)
        let avgActivity = activities.isEmpty ? 0 : activities.reduce(0, +) / Float(activities.count)
        let summary = String(
            format: "%d turns, %d speakers, %.1fs speech, avg activity %.2f",
            segments.count, speakers, speech, avgActivity
        )
        logger.log("Diarized \(fileURL.lastPathComponent, privacy: .public): \(summary, privacy: .public)")

        guard ProcessInfo.processInfo.environment["HARK_DIARIZATION_DEBUG"] != nil else { return }
        let dump = segments.map {
            DebugSegment(
                start: Double($0.startTime),
                end: Double($0.endTime),
                speaker: $0.speakerIndex,
                activity: Double($0.activity)
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
        let speaker: Int
        let activity: Double
    }
}

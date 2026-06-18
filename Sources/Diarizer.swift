import FluidAudio
import Foundation

/// Diarizes the system-audio track into speaker turns with FluidAudio's on-device
/// CoreML pipeline. Owns the non-`Sendable` `OfflineDiarizerManager` on a single
/// isolation domain so the models, which load lazily on the first call and are then
/// cached, are only ever touched from one place.
actor Diarizer {
    /// `OfflineDiarizerManager` is non-Sendable and its `process` is nonisolated, so the
    /// compiler can't see that the actor already serializes every use. We transcribe one
    /// session at a time, so the manager is never touched concurrently; `nonisolated(unsafe)`
    /// states that we own that guarantee rather than the type system.
    private nonisolated(unsafe) let manager = OfflineDiarizerManager()

    /// Diarizes a 16 kHz mono recording into turns sorted by start time. FluidAudio
    /// downloads and compiles its models on the first call, then reuses them.
    /// - Returns: the speaker turns, or an empty array when the track is silent.
    func turns(in fileURL: URL) async throws -> [DiarizationTurn] {
        do {
            let result = try await manager.process(fileURL)
            return result.segments
                .map {
                    DiarizationTurn(
                        start: Double($0.startTimeSeconds),
                        end: Double($0.endTimeSeconds),
                        speakerId: $0.speakerId
                    )
                }
                .sorted { $0.start < $1.start }
        } catch OfflineDiarizationError.noSpeechDetected {
            return []
        } catch let error as OfflineDiarizationError {
            throw TranscriptionError.diarizationFailed(error.localizedDescription)
        }
    }
}

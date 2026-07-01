import AVFoundation
import FluidAudio
import Foundation
import OSLog

/// Transcribes a recording's track into timed tokens with FluidAudio's on-device Parakeet TDT
/// v3 model. The `AsrManager` is loaded once and cached on this actor, then reused for every track.
actor Transcriber {
    private let logger = Logger(category: "Transcriber")

    private var manager: AsrManager?

    /// Used to check for silent or too-short tracks.
    private static let minimumSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)
    private static let modelSampleRate = Double(ASRConstants.sampleRate)

    /// Transcribes one 16 kHz mono track into tokens carrying per-token start/end times.
    /// - Parameters:
    ///   - locale: hints the multilingual model's script filtering (ignored when its language
    ///     isn't one Parakeet recognizes).
    /// - Returns: the timed tokens, or an empty array when the track is silent or too short.
    func tokens(in fileURL: URL, locale: Locale) async throws -> [TimedToken] {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw TranscriptionError.unreadableAudio(fileURL)
        }
        let format = audioFile.processingFormat
        let modelRateSamples = Double(audioFile.length) * Self.modelSampleRate / format.sampleRate
        let estimatedSamples = Int(modelRateSamples.rounded(.up))
        guard estimatedSamples >= Self.minimumSamples else { return [] }

        let manager = try await loadedManager()
        let result: ASRResult
        do {
            // A fresh decoder state per track keeps the two tracks' passes independent.
            var state = try TdtDecoderState()
            result = try await manager.transcribe(fileURL, decoderState: &state, language: Self.language(for: locale))
        } catch {
            throw TranscriptionError.transcriptionFailed(String(describing: error))
        }

        guard let timings = result.tokenTimings else { return [] }
        let tokens = timings.map { TimedToken(start: $0.startTime, end: $0.endTime, text: $0.token) }
        logSummary(result, tokens: tokens, for: fileURL)
        return tokens
    }

    private func loadedManager() async throws -> AsrManager {
        if let manager { return manager }
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let config = ASRConfig(
                parallelChunkConcurrency: Preferences.asrParallelChunkConcurrency,
                dualDecodeArbitration: Preferences.asrUsesDualDecodeArbitration
            )
            let loaded = AsrManager(config: config, models: models)
            manager = loaded
            return loaded
        } catch {
            throw TranscriptionError.transcriptionFailed("couldn't load the transcription model: \(error)")
        }
    }

    /// Maps a locale to a Parakeet language hint, or `nil` when the model has no matching script
    /// filter for it.
    private static func language(for locale: Locale) -> Language? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        return Language(rawValue: code)
    }

    private func logSummary(_ result: ASRResult, tokens: [TimedToken], for fileURL: URL) {
        let summary = String(
            format: "%d tokens, %.1fs audio, confidence %.2f, %.1fx realtime",
            tokens.count, result.duration, result.confidence, result.rtfx
        )
        logger.log("Transcribed \(fileURL.lastPathComponent, privacy: .public): \(summary, privacy: .public)")
        writeDebugDump(tokens, for: fileURL)
    }

    // MARK: Debug

    /// When `HARK_ASR_DEBUG` is set, writes the raw tokens to `asr.<track>.debug.json` next to the
    /// input for tuning the utterance gap.
    private func writeDebugDump(_ tokens: [TimedToken], for fileURL: URL) {
        guard ProcessInfo.processInfo.flag(forKey: "HARK_ASR_DEBUG") else { return }
        let track = fileURL.deletingPathExtension().lastPathComponent
        let debugURL = fileURL.deletingLastPathComponent().appendingPathComponent("asr.\(track).debug.json")
        do {
            try tokens.map(DebugToken.init).writeJSON(to: debugURL, sortedKeys: true)
        } catch {
            logger.error("Couldn't write ASR debug dump: \(error, privacy: .public)")
        }
    }

    /// One token in the `HARK_ASR_DEBUG` dump.
    private struct DebugToken: Encodable {
        let start: Double
        let end: Double
        let text: String

        init(_ token: TimedToken) {
            start = token.start
            end = token.end
            text = token.text
        }
    }
}

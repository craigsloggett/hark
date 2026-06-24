import AppIntents

struct StopAndTranscribeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Hark Recording & Transcribe"
    static let description = IntentDescription(
        "Stops the current recording and transcribes it to disk."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AudioRecorder.shared.stopAndTranscribe()
        return .result(dialog: "Stopped recording. Transcribing.")
    }
}

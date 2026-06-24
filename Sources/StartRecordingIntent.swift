import AppIntents

/// Starts a new recording.
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Hark Recording"
    static let description = IntentDescription("Starts a new recording.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AudioRecorder.shared.start()
        return .result(dialog: "Started recording.")
    }
}

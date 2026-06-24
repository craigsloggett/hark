import AppIntents

struct ToggleRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Hark Recording"
    static let description = IntentDescription(
        "Starts a recording, or stops the current one and transcribes it to disk."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let wasRecording = await AudioRecorder.shared.isRecording
        await AudioRecorder.shared.toggleRecording()
        return .result(
            dialog: wasRecording ? "Stopped recording. Transcribing." : "Started recording."
        )
    }
}

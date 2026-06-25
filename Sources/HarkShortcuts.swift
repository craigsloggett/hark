import AppIntents

/// Surfaces Hark's recording intents to Spotlight, the Shortcuts app, and Siri.
struct HarkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "Toggle recording in \(.applicationName)",
                "Toggle \(.applicationName) recording",
            ],
            shortTitle: "Toggle Recording",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Start a \(.applicationName) recording",
            ],
            shortTitle: "Start Recording",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopAndTranscribeIntent(),
            phrases: [
                "Stop recording in \(.applicationName)",
                "Stop the \(.applicationName) recording",
            ],
            shortTitle: "Stop & Transcribe",
            systemImageName: "stop.circle"
        )
    }
}

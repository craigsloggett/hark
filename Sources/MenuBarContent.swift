import AppKit
import SwiftUI

/// The menu shown when the user clicks Hark's menu bar item.
struct MenuBarContent: View {
    @Environment(AudioRecorder.self) private var recorder
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)

        Divider()

        Button(recorder.isRecording ? "Stop & Transcribe" : "Start Recording") {
            recorder.toggleAndTranscribe()
        }

        Button("Transcribe Last Session") {
            recorder.transcribeLastSession()
        }
        .disabled(!canTranscribe)

        Divider()

        Button("Open Last Transcript") {
            if let lastTranscriptURL {
                NSWorkspace.shared.open(lastTranscriptURL)
            }
        }
        .disabled(lastTranscriptURL == nil)

        Button("Reveal Last Session in Finder") {
            if let session = recorder.lastSessionURL {
                NSWorkspace.shared.activateFileViewerSelecting([session])
            }
        }
        .disabled(recorder.lastSessionURL == nil)

        Divider()

        Button("Settings…") {
            showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Hark") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var statusText: String {
        switch recorder.transcriptionState {
        case .running:
            "Transcribing…"
        case .failed:
            "Transcription failed"
        case .finished, .idle:
            recorder.isRecording ? "Recording…" : "Ready"
        }
    }

    private var canTranscribe: Bool {
        recorder.lastSessionURL != nil
            && !recorder.isRecording
            && recorder.transcriptionState != .running
    }

    private var lastTranscriptURL: URL? {
        guard case let .finished(url) = recorder.transcriptionState else { return nil }
        return url
    }

    private func showSettings() {
        // A menu bar (accessory) app must activate itself to bring the window to the front.
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: SettingsWindow.id)
    }
}

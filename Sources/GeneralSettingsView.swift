import AppKit
import SwiftUI

/// General settings: how to drive Hark with a global keyboard shortcut.
struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text(
                    "Hark works with a keyboard shortcut you choose. You set it up in the "
                        + "Shortcuts app, which also lets you start Hark from Spotlight or by "
                        + "asking Siri."
                )
                .foregroundStyle(.secondary)
            }

            Section("Set Up a Keyboard Shortcut") {
                Text(
                    "Open the Shortcuts app and create a shortcut that runs Hark's “Toggle Hark "
                        + "Recording” action, then assign it a keyboard shortcut. Press it once to "
                        + "start recording, and again to stop and transcribe."
                )
                Button("Open Shortcuts…") { openShortcutsApp() }
            }

            Section("Available Actions") {
                Label("Toggle Hark Recording", systemImage: "record.circle")
                Label("Start Hark Recording", systemImage: "record.circle")
                Label("Stop Hark Recording & Transcribe", systemImage: "stop.circle")
            }
        }
        .formStyle(.grouped)
    }

    private func openShortcutsApp() {
        // Shortcuts registers the "shortcuts" URL scheme; guard rather than force-unwrap.
        guard let url = URL(string: "shortcuts://") else { return }
        NSWorkspace.shared.open(url)
    }
}

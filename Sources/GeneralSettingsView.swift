import AppKit
import SwiftUI

/// General settings: how to drive Hark with a global keyboard shortcut.
struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text(
                    "Hark is driven by a global keyboard shortcut. macOS has no built-in API for "
                        + "app hotkeys, so Hark exposes its actions to the Shortcuts app, where you "
                        + "assign the keyboard shortcut (and can also run it from Spotlight or Siri)."
                )
                .foregroundStyle(.secondary)
            }

            Section("Set Up a Keyboard Shortcut") {
                Text(
                    "In the Shortcuts app, create a shortcut that runs Hark's “Toggle Hark "
                        + "Recording” action, then give that shortcut a keyboard shortcut. Pressing "
                        + "it starts a recording; pressing it again stops and transcribes."
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

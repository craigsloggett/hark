import AppKit
import SwiftUI

/// General settings covering Hark's window posture, privacy, and the global keyboard shortcut.
struct GeneralSettingsView: View {
    @AppStorage(Preferences.Key.menuBarOnly)
    private var isMenuBarOnly = Preferences.Default.isMenuBarOnly

    @AppStorage(Preferences.Key.showMenuBarIcon)
    private var showsMenuBarIcon = Preferences.Default.showsMenuBarIcon

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hark")
                            .font(.headline)
                        Text("Meeting transcripts that know who said what. Private, on your Mac.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Menu Bar") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Keep Hark in the menu bar only", isOn: $isMenuBarOnly)
                    Text(
                        "Hark stays out of the Dock and opens no window at launch. Everything stays "
                            + "reachable from the menu bar icon."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    // Forced on and locked in menu-bar-only mode, so it shows the effective state
                    // without overwriting the stored choice.
                    Toggle("Show the menu bar icon", isOn: isMenuBarOnly ? .constant(true) : $showsMenuBarIcon)
                        .disabled(isMenuBarOnly)
                    Text("Always on in menu-bar-only mode, where the icon is the only way to reach Hark.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Label {
                    Text(
                        "Recording, transcription, and voice recognition all happen on this Mac. "
                            + "Hark has no account, no cloud service, and nothing leaves your device."
                    )
                    .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "hand.raised")
                }
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
        .fixedSize(horizontal: false, vertical: true)
        // Apply the mode switch immediately; this view is the only writer, so no defaults observer.
        .onChange(of: isMenuBarOnly) {
            WindowActivation.shared.apply()
        }
    }

    private func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        NSWorkspace.shared.open(url)
    }
}

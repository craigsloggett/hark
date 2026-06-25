import SwiftUI

/// Identifies the settings window so the menu can open it with `openWindow`.
enum SettingsWindow {
    static let id = "settings"
}

/// The tabbed settings window: general app options and advanced transcription tuning.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480)
    }
}

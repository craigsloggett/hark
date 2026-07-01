import SwiftUI

/// Identifies the settings window so the menu can open it with `openWindow`.
enum SettingsWindow {
    static let id = "settings"
}

/// The tabbed settings window holding general app options and advanced transcription tuning.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        // Pin the width and let the tabs set the height so `.windowResizability(.contentSize)` can
        // size the window to each pane and keep it non-resizable, the native Settings-window behavior.
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

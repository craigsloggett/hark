import SwiftUI

/// Identifies the settings window so the menu can open it with `openWindow`.
enum SettingsWindow {
    static let id = "settings"
}

/// The tabbed settings window holding general app options and advanced transcription tuning.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
            }

            Tab("Advanced", systemImage: "slider.horizontal.3") {
                // Size the pane to the General tab's intrinsic height so switching tabs never
                // resizes the window; the Advanced form scrolls within that height.
                GeneralSettingsView()
                    .hidden()
                    .overlay { AdvancedSettingsView() }
            }
        }
        // Pin the width and let the tabs set the height so `.windowResizability(.contentSize)` can
        // size the window to each pane and keep it non-resizable, the native Settings-window behavior.
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

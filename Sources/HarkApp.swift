import SwiftUI

@main
struct HarkApp: App {
    @State private var recorder = AudioRecorder.shared

    init() {
        Preferences.register()
    }

    var body: some Scene {
        // Inject at the view level inside each closure: a Scene-level `.environment` does not
        // propagate into a MenuBarExtra's separately-hosted label and content views.
        MenuBarExtra {
            MenuBarContent()
                .environment(recorder)
        } label: {
            MenuBarLabel()
                .environment(recorder)
        }
        .menuBarExtraStyle(.menu)

        // A plain Window, not a Settings scene: `openSettings()` is unreliable from a menu bar
        // app on macOS 26, while `openWindow` is not. Suppressed so it never opens at launch.
        Window("Hark Settings", id: SettingsWindow.id) {
            SettingsView()
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
    }
}

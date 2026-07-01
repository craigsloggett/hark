import SwiftUI

@main
struct HarkApp: App {
    @State private var recorder = AudioRecorder.shared

    init() {
        Preferences.register()
        Preferences.Launch.capture()
    }

    var body: some Scene {
        // MenuBarExtra hosts its label and content in separate views, so the recorder is injected
        // into each closure.
        MenuBarExtra {
            MenuBarContent()
                .environment(recorder)
        } label: {
            MenuBarLabel()
                .environment(recorder)
        }
        .menuBarExtraStyle(.menu)

        // A window opened by id via `openWindow` (`openSettings()` is unreliable from a menu bar
        // app on macOS 26). Suppressed so it never opens at launch.
        Window("Hark Settings", id: SettingsWindow.id) {
            SettingsView()
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)

        // The recordings browser and speaker-labeling window. A singleton so re-opening refocuses the
        // one instance; not state-restored so every appearance flows through the activation counter.
        Window("Hark", id: SessionsWindow.id) {
            SessionsBrowserView()
                .environment(recorder)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 900, height: 620)
    }
}

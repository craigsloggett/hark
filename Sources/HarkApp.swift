import SwiftUI

@main
struct HarkApp: App {
    @NSApplicationDelegateAdaptor(HarkAppDelegate.self) private var appDelegate
    @State private var recorder = AudioRecorder.shared

    @AppStorage(Preferences.Key.menuBarOnly)
    private var isMenuBarOnly = Preferences.Default.isMenuBarOnly

    @AppStorage(Preferences.Key.showMenuBarIcon)
    private var showsMenuBarIcon = Preferences.Default.showsMenuBarIcon

    init() {
        Preferences.register()
        Preferences.Launch.capture()
    }

    var body: some Scene {
        // MenuBarExtra hosts its label and content in separate views, so the recorder is injected
        // into each closure.
        MenuBarExtra(isInserted: menuBarIconInserted) {
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
        // one instance; not state-restored so every appearance flows through the activation counter and
        // its launch presentation stays governed by the menu-bar-only preference rather than saved state.
        Window("Hark", id: SessionsWindow.id) {
            SessionsBrowserView()
                .environment(recorder)
        }
        .defaultLaunchBehavior(isMenuBarOnly ? .suppressed : .presented)
        .restorationBehavior(.disabled)
        .defaultSize(width: 900, height: 620)
    }

    /// Forced visible in menu-bar-only mode, where the icon is the only way back into the app. The
    /// setter still records the user's choice, since macOS writes `false` when the icon is
    /// command-dragged out of the menu bar.
    private var menuBarIconInserted: Binding<Bool> {
        Binding(
            get: { showsMenuBarIcon || isMenuBarOnly },
            set: { showsMenuBarIcon = $0 }
        )
    }
}

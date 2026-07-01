import SwiftUI

/// Identifies the settings window so the menu can open it with `openWindow`.
enum SettingsWindow {
    static let id = "settings"
}

/// The settings window's tabs, so a menu command can open the window on a specific pane.
enum SettingsTab {
    case general
    case voices
    case advanced
}

/// Which settings tab is shown. A menu command (e.g. "Name Speakers…") sets this before opening the
/// window so it lands on the right pane.
@MainActor
@Observable
final class SettingsPresenter {
    static let shared = SettingsPresenter()
    var tab: SettingsTab = .general
}

/// The tabbed settings window holding general options, saved-voice naming, and advanced tuning.
struct SettingsView: View {
    @State private var presenter = SettingsPresenter.shared

    var body: some View {
        TabView(selection: $presenter.tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            VoicesSettingsView()
                .tabItem { Label("Voices", systemImage: "person.wave.2") }
                .tag(SettingsTab.voices)

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)
        }
        // Pin the width and let the tabs set the height so `.windowResizability(.contentSize)` can
        // size the window to each pane and keep it non-resizable, the native Settings-window behavior.
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

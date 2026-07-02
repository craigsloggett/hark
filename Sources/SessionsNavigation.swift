import Observation

/// Carries a one-shot navigation request from the menu bar into the sessions window, which owns
/// its selection state per-window.
@MainActor
@Observable
final class SessionsNavigation {
    static let shared = SessionsNavigation()

    /// Set by the menu to ask the sessions window to select the newest transcript; the window
    /// resets it after consuming.
    var wantsLatest = false
}

import AppKit

/// Without `LSUIElement` the process launches as a regular Dock app, so in menu-bar-only mode it
/// demotes itself at the earliest delegate callback; a brief Dock-icon flash is the accepted cost.
@MainActor
final class HarkAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        WindowActivation.shared.apply()
    }
}

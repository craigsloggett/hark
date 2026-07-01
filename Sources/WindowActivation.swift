import AppKit

/// Promotes the app from a menu-bar accessory to a regular Dock app while the recordings window is
/// open, and back to accessory when the last one closes. Driven by the window root's appear and
/// disappear so a relaunch or state restoration flows through the same counter as a menu open.
@MainActor
final class WindowActivation {
    static let shared = WindowActivation()

    private var openCount = 0

    /// Called by a menu command before the window mounts so the Dock icon appears immediately.
    func promote() {
        setPolicy(.regular)
    }

    func didOpen() {
        openCount += 1
        setPolicy(.regular)
    }

    func didClose() {
        openCount = max(0, openCount - 1)
        if openCount == 0 {
            setPolicy(.accessory)
        }
    }

    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        NSApp.setActivationPolicy(policy)
        // A change out of `.accessory` does not bring the app forward on its own.
        NSApp.activate(ignoringOtherApps: true)
    }
}

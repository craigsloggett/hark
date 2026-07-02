import AppKit

/// Owns the app's activation policy across its two modes. Windowed mode stays a regular Dock app;
/// menu-bar-only mode rests as an accessory and promotes to regular only while the recordings window
/// is open, dropping back when the last one closes. Driven by the window root's appear and disappear,
/// by the launch delegate, and by the menu-bar-only toggle, all of which recompute the same policy.
@MainActor
final class WindowActivation {
    static let shared = WindowActivation()

    private var openCount = 0

    /// Called by a menu command before the window mounts so the Dock icon appears immediately, then
    /// activates so the window comes forward (a menu bar click does not activate the app on its own).
    func promote() {
        setPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func didOpen() {
        openCount += 1
        apply()
    }

    func didClose() {
        openCount = max(0, openCount - 1)
        apply()
    }

    /// Recomputes the policy from the mode and the open-window count; called at launch and when the
    /// menu-bar-only preference changes so a Settings toggle takes effect without a relaunch.
    func apply() {
        let isAccessory = Preferences.isMenuBarOnly && openCount == 0
        setPolicy(isAccessory ? .accessory : .regular)
    }

    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        // Idempotent: windowed-mode open and close events leave the policy untouched instead of
        // re-activating the app on every window event.
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // A change out of `.accessory` does not attach the main menu until the app activates.
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

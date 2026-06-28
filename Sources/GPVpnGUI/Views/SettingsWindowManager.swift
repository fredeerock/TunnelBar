import SwiftUI
import AppKit

/// Lazily creates and shows the Settings window. The app is a menu-bar agent
/// (LSUIElement), so the window is managed manually rather than via a SwiftUI
/// Window/Settings scene (which would otherwise open at launch).
@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    func show(app: AppState) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(app))
            let window = NSWindow(contentViewController: hosting)
            window.title = "TunnelBar"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 460, height: 460))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

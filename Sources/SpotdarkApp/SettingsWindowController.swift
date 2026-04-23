import AppKit
import SwiftUI
import SpotdarkCore

/// Manages the settings window directly, bypassing SwiftUI's Settings scene
/// activation path which is unreliable for .accessory apps.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private lazy var window: NSWindow = makeWindow()

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(store: SettingsStore.shared))
        let w = NSWindow(contentViewController: hosting)
        w.title = ""
        w.titleVisibility = .hidden
        w.titlebarSeparatorStyle = .none
        w.titlebarAppearsTransparent = true
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 820, height: 520))
        w.minSize = NSSize(width: 640, height: 400)
        w.center()
        w.delegate = self
        return w
    }

    func show(pane: SettingsPane? = nil) {
        if let pane {
            SettingsStore.shared.selectedPane = pane
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Nothing to clean up; window stays allocated for reuse.
    }
}

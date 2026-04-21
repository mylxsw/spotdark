import AppKit
import SwiftUI
import SpotdarkCore

/// A borderless panel that can become key/main to accept text input.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosts the SwiftUI launcher view inside an NSPanel.
@MainActor
final class LauncherPanelController {
    private let panel: LauncherPanel
    private let store: LauncherStore

    var isVisible: Bool {
        panel.isVisible
    }

    init() {
        let commandRegistry = CommandRegistry(commands: [
            CommandItem(id: "open-settings", title: "Open Settings", keywords: ["settings", "preferences"]),
            CommandItem(id: "quit", title: "Quit", keywords: ["exit", "close"])
        ])

        // App indexing is wired via a Spotlight index stream in the store.
        store = LauncherStore(commandProvider: commandRegistry)

        let rootView = LauncherRootView(store: store)
        let hosting = NSHostingController(rootView: rootView)

        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true

        if #available(macOS 13.0, *) {
            panel.toolbarStyle = .unifiedCompact
        }

        panel.contentViewController = hosting

        // Make SwiftUI background transparent; SwiftUI draws its own material.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func showCenteredAndFocus() {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Ensure the search field becomes focused.
        store.requestFocus()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

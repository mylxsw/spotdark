import AppKit
import QuartzCore
import SwiftUI
import SpotdarkCore

private let savedPanelOriginKey = "settings.savedPanelFrame"

/// A borderless panel that can become key/main to accept text input.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosts the SwiftUI launcher view inside an NSPanel.
@MainActor
final class LauncherPanelController: NSObject {
    private let panel: LauncherPanel
    private let store: LauncherStore

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        let commandRegistry = CommandRegistry(commands: [
            CommandItem(id: "open-settings", title: "Open Settings", keywords: ["settings", "preferences"]),
            CommandItem(id: "quit", title: "Quit", keywords: ["exit", "close"])
        ])

        // App indexing follows the directories configured in Settings.
        store = LauncherStore(
            commandProvider: commandRegistry,
            indexStream: SettingsAppIndexStream(settingsStore: .shared)
        )

        let rootView = LauncherRootView(store: store)
        let hosting = NSHostingController(rootView: rootView)

        panel = LauncherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: LauncherPanelMetrics.width,
                height: LauncherPanelMetrics.collapsedHeight
            ),
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
        panel.animationBehavior = .utilityWindow

        if #available(macOS 13.0, *) {
            panel.toolbarStyle = .unifiedCompact
        }

        panel.contentViewController = hosting

        // Make SwiftUI background transparent; SwiftUI draws its own material.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        super.init()

        panel.delegate = self
        store.onPanelHeightChange = { [weak self] height, animated in
            self?.updatePanelHeight(height, animated: animated)
        }
        updatePanelHeight(store.preferredPanelHeight, animated: false)
        centerOnScreen()
    }

    func showCenteredAndFocus() {
        store.prepareForPresentation()
        if SettingsStore.shared.remembersPanelPosition, let savedOrigin = restoredPanelOrigin(for: store.preferredPanelHeight) {
            panel.setFrameOrigin(savedOrigin)
        } else {
            centerOnScreen()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let origin = NSPoint(
            x: round(frame.midX - panel.frame.width / 2),
            y: round(frame.midY - panel.frame.height / 2)
        )
        panel.setFrameOrigin(origin)
    }

    private func restoredPanelOrigin(for height: CGFloat) -> NSPoint? {
        guard let data = UserDefaults.standard.dictionary(forKey: savedPanelOriginKey),
              let x = data["x"] as? Double else {
            return nil
        }

        if let top = data["top"] as? Double {
            return NSPoint(x: x, y: top - height)
        }

        guard let y = data["y"] as? Double else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func updatePanelHeight(_ height: CGFloat, animated: Bool) {
        let currentFrame = panel.frame
        guard abs(currentFrame.height - height) > 0.5 else { return }

        let newFrame = NSRect(
            x: round(currentFrame.origin.x),
            y: round(currentFrame.maxY - height),
            width: LauncherPanelMetrics.width,
            height: height
        ).integral

        guard animated, panel.isVisible else {
            panel.setFrame(newFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = LauncherPanelMetrics.panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }
}

extension LauncherPanelController: NSWindowDelegate {
    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard SettingsStore.shared.remembersPanelPosition else { return }
            let frame = panel.frame
            UserDefaults.standard.set(
                ["x": frame.origin.x, "top": frame.maxY],
                forKey: savedPanelOriginKey
            )
        }
    }
}

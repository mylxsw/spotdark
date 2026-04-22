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
    private var visibilityAnimationID: UInt = 0
    private var suppressedFramePersistenceCount = 0

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        let commandRegistry = CommandRegistry(commands: [
            CommandItem(id: "open-settings", title: "Open Settings", keywords: ["settings", "preferences"]),
            CommandItem(id: "quit", title: "Quit", keywords: ["exit", "close"])
        ])

        PluginManager.shared.register(searchSource: SystemInfoPlugin())
        PluginManager.shared.register(searchSource: ClipboardHistoryPlugin())
        PluginManager.shared.register(action: SystemCommandsPlugin())
        ClipboardHistoryStore.shared.startMonitoring()

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
            withSuppressedFramePersistence {
                panel.setFrameOrigin(savedOrigin)
            }
        } else {
            centerOnScreen()
        }

        let finalFrame = panel.frame.integral
        let initialFrame = finalFrame.offsetBy(dx: 0, dy: LauncherPanelMetrics.panelPresentationOffset).integral
        let animationID = nextVisibilityAnimationID()

        NSApp.activate(ignoringOtherApps: true)
        beginSuppressingFramePersistence()
        panel.alphaValue = panel.isVisible ? panel.alphaValue : 0
        panel.setFrame(initialFrame, display: false)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = LauncherPanelMetrics.panelPresentationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.endSuppressingFramePersistence()

                guard animationID == self.visibilityAnimationID else { return }
                self.panel.alphaValue = 1
            }
        }
    }

    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        // Use screen.frame for horizontal center so a side Dock doesn't shift midX.
        // Use visibleFrame for vertical center so the panel stays above a bottom Dock.
        let x = round(screen.frame.midX - panel.frame.width / 2)
        let y = round(screen.visibleFrame.midY - panel.frame.height / 2)
        withSuppressedFramePersistence {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func restoredPanelOrigin(for height: CGFloat) -> NSPoint? {
        guard let data = UserDefaults.standard.dictionary(forKey: savedPanelOriginKey) else {
            return nil
        }

        return LauncherPanelPositioning.restoredOrigin(
            from: data,
            panelSize: CGSize(width: LauncherPanelMetrics.width, height: height),
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
    }

    func hide() {
        guard panel.isVisible else { return }

        let animationID = nextVisibilityAnimationID()
        let targetFrame = panel.frame
            .offsetBy(dx: 0, dy: LauncherPanelMetrics.panelPresentationOffset * 0.7)
            .integral

        beginSuppressingFramePersistence()
        panel.alphaValue = max(panel.alphaValue, 0.001)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = LauncherPanelMetrics.panelDismissalDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.endSuppressingFramePersistence()

                guard animationID == self.visibilityAnimationID else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
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
            withSuppressedFramePersistence {
                panel.setFrame(newFrame, display: true)
            }
            return
        }

        beginSuppressingFramePersistence()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = LauncherPanelMetrics.panelResizeAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.endSuppressingFramePersistence()
            }
        }
    }

    private func nextVisibilityAnimationID() -> UInt {
        visibilityAnimationID &+= 1
        return visibilityAnimationID
    }

    private func beginSuppressingFramePersistence() {
        suppressedFramePersistenceCount += 1
    }

    private func endSuppressingFramePersistence() {
        suppressedFramePersistenceCount = max(0, suppressedFramePersistenceCount - 1)
    }

    private func withSuppressedFramePersistence(_ action: () -> Void) {
        beginSuppressingFramePersistence()
        action()
        endSuppressingFramePersistence()
    }
}

extension LauncherPanelController: NSWindowDelegate {
    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard SettingsStore.shared.remembersPanelPosition,
                  suppressedFramePersistenceCount == 0 else { return }
            let frame = panel.frame
            UserDefaults.standard.set(
                ["x": frame.origin.x, "top": frame.maxY],
                forKey: savedPanelOriginKey
            )
        }
    }
}

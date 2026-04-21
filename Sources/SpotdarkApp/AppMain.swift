import AppKit
import SwiftUI
import SpotdarkCore

/// A global singleton that owns the launcher panel.
@MainActor
final class LauncherCoordinator {
    static let shared = LauncherCoordinator()

    private let panelController: LauncherPanelController

    private init() {
        panelController = LauncherPanelController()
    }

    func toggle() {
        if panelController.isVisible {
            panelController.hide()
        } else {
            panelController.showCenteredAndFocus()
        }
    }

    func show() {
        panelController.showCenteredAndFocus()
    }

    func hide() {
        panelController.hide()
    }
}

/// Application delegate for hotkey registration and menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager: HotKeyRegistering = CarbonHotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotKey()
        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
    }

    private func registerHotKey() {
        do {
            try hotKeyManager.register(hotKey: .commandSpace) {
                Task { @MainActor in
                    LauncherCoordinator.shared.toggle()
                }
            }
        } catch {
            showHotKeyRegistrationFailedAlert()

            do {
                try hotKeyManager.register(hotKey: .optionSpace) {
                    Task { @MainActor in
                        LauncherCoordinator.shared.toggle()
                    }
                }
            } catch {
                // If both registrations fail, the user can still open the launcher from the menu.
            }
        }
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(title: "Show Launcher", action: #selector(showLauncherFromMenu), keyEquivalent: "l"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        NSApp.mainMenu = mainMenu
    }

    private func showHotKeyRegistrationFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Cannot register Command+Space"
        alert.informativeText = "Command+Space is likely reserved by Spotlight. Disable Spotlight's shortcut in System Settings to use it here. Falling back to Option+Space."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func showLauncherFromMenu() {
        Task { @MainActor in
            LauncherCoordinator.shared.show()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@main
struct SpotdarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No default windows; this behaves like a menu bar accessory.
        Settings {
            EmptyView()
        }
    }
}

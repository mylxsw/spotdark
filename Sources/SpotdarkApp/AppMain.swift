import AppKit
import SwiftUI
import SpotdarkCore

/// A global singleton that owns the launcher panel.
@MainActor
final class LauncherCoordinator {
    static let shared = LauncherCoordinator()

    private let panelController: LauncherPanelController
    private let errorFeedbackController: ErrorFeedbackPanelController

    private init() {
        panelController = LauncherPanelController()
        errorFeedbackController = ErrorFeedbackPanelController()
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

    func showErrorFeedback(_ content: ErrorFeedbackContent) {
        errorFeedbackController.present(content)
    }

    func showSettings(pane: SettingsPane? = nil) {
        if let pane {
            SettingsStore.shared.selectedPane = pane
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

/// Application delegate for hotkey registration and menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager: HotKeyRegistering = NSEventHotKeyManager()
    private let settingsStore = SettingsStore.shared

    private var activeHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hotKeyManager.onError = { error in
            LauncherCoordinator.shared.showErrorFeedback(.hotKeyError(error))
        }
        settingsStore.applyLauncherHotKey = { [weak self] hotKey in
            self?.replaceLauncherHotKey(with: hotKey) ?? .failure(.monitorRegistrationFailed)
        }
        registerHotKey()
        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsStore.applyLauncherHotKey = nil
        hotKeyManager.unregisterAll()
    }

    private func registerHotKey() {
        do {
            try registerLauncherHotKey(settingsStore.launcherHotKey)
            activeHotKey = settingsStore.launcherHotKey
        } catch let error as HotKeyError {
            LauncherCoordinator.shared.showErrorFeedback(.hotKeyError(error))
        } catch {
            LauncherCoordinator.shared.showErrorFeedback(.shortcutMonitorError)
        }
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(NSMenuItem(title: SettingsStrings.showLauncherMenuItemTitle, action: #selector(showLauncherFromMenu), keyEquivalent: "l"))
        appMenu.addItem(NSMenuItem(title: SettingsStrings.settingsMenuItemTitle, action: #selector(showSettingsFromMenu), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: SettingsStrings.quitMenuItemTitle, action: #selector(quit), keyEquivalent: "q"))

        NSApp.mainMenu = mainMenu
    }

    private func registerLauncherHotKey(_ hotKey: HotKey) throws {
        try hotKeyManager.register(hotKey: hotKey) {
            Task { @MainActor in
                LauncherCoordinator.shared.toggle()
            }
        }
    }

    private func replaceLauncherHotKey(with hotKey: HotKey) -> Result<Void, HotKeyError> {
        let previousHotKey = activeHotKey
        hotKeyManager.unregisterAll()

        do {
            try registerLauncherHotKey(hotKey)
            activeHotKey = hotKey
            return .success(())
        } catch let error as HotKeyError {
            if let previousHotKey {
                try? registerLauncherHotKey(previousHotKey)
                activeHotKey = previousHotKey
            }
            LauncherCoordinator.shared.showErrorFeedback(.hotKeyError(error))
            return .failure(error)
        } catch {
            if let previousHotKey {
                try? registerLauncherHotKey(previousHotKey)
                activeHotKey = previousHotKey
            }
            LauncherCoordinator.shared.showErrorFeedback(.shortcutMonitorError)
            return .failure(.monitorRegistrationFailed)
        }
    }

    @objc private func showLauncherFromMenu() {
        Task { @MainActor in
            LauncherCoordinator.shared.show()
        }
    }

    @objc private func showSettingsFromMenu() {
        Task { @MainActor in
            LauncherCoordinator.shared.showSettings()
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
            SettingsView(store: settingsStore)
        }
    }

    private var settingsStore: SettingsStore {
        SettingsStore.shared
    }
}

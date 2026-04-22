import AppKit
import SpotdarkCore

final class SystemCommandsPlugin: ActionPlugin, @unchecked Sendable {
    let pluginID = "com.spotdark.system-commands"
    let displayName = "System Commands"

    func commands() -> [CommandItem] {
        [
            CommandItem(id: "system.lock-screen", title: "Lock Screen",
                        keywords: ["lock", "screen", "secure", "lockscreen"]),
            CommandItem(id: "system.sleep", title: "Sleep",
                        keywords: ["sleep", "hibernate", "suspend"]),
            CommandItem(id: "system.restart", title: "Restart",
                        keywords: ["restart", "reboot"]),
            CommandItem(id: "system.shutdown", title: "Shut Down",
                        keywords: ["shutdown", "shut down", "power off", "poweroff", "halt"]),
            CommandItem(id: "system.empty-trash", title: "Empty Trash",
                        keywords: ["trash", "empty", "bin", "garbage"]),
        ]
    }

    func handle(commandID: String) {
        switch commandID {
        case "system.lock-screen":
            lockScreen()
        case "system.sleep":
            sleepMac()
        case "system.restart":
            // Defer so the launcher hides before the confirmation dialog appears.
            DispatchQueue.main.async { self.confirmDangerous(title: "Restart", action: self.restart) }
        case "system.shutdown":
            DispatchQueue.main.async { self.confirmDangerous(title: "Shut Down", action: self.shutdown) }
        case "system.empty-trash":
            emptyTrash()
        default:
            break
        }
    }

    // MARK: - Helpers

    private func confirmDangerous(title: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Are you sure you want to \(title.lowercased()) your Mac?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: title)
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }

    private func lockScreen() {
        let cgSessionPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cgSessionPath)
        task.arguments = ["-suspend"]
        try? task.run()
    }

    private func sleepMac() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["sleepnow"]
        try? task.run()
    }

    private func restart() {
        let src = "tell application \"System Events\" to restart"
        NSAppleScript(source: src)?.executeAndReturnError(nil)
    }

    private func shutdown() {
        let src = "tell application \"System Events\" to shut down"
        NSAppleScript(source: src)?.executeAndReturnError(nil)
    }

    private func emptyTrash() {
        let src = "tell application \"Finder\" to empty trash"
        NSAppleScript(source: src)?.executeAndReturnError(nil)
    }
}

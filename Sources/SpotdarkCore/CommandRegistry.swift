import Foundation

/// Provides a list of in-app commands.
public protocol CommandProviding {
    func allCommands() -> [CommandItem]
}

/// A simple in-memory command registry.
public final class CommandRegistry: CommandProviding {
    private var commands: [CommandItem]

    public init(commands: [CommandItem] = []) {
        self.commands = commands
    }

    public func register(_ command: CommandItem) {
        // Replace on same id.
        commands.removeAll { $0.id == command.id }
        commands.append(command)
    }

    public func allCommands() -> [CommandItem] {
        commands
    }
}

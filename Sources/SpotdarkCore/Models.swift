import Foundation

/// A unified search item.
public enum SearchItem: Equatable {
    case application(AppItem)
    case command(CommandItem)
}

/// Represents a macOS application bundle that can be launched.
public struct AppItem: Equatable, Hashable {
    public let name: String
    public let bundleIdentifier: String?
    public let bundleURL: URL

    public init(name: String, bundleIdentifier: String?, bundleURL: URL) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
    }
}

/// Represents an executable command (not a shell command, but an in-app action).
public struct CommandItem: Equatable, Hashable {
    public let id: String
    public let title: String
    public let keywords: [String]

    public init(id: String, title: String, keywords: [String]) {
        self.id = id
        self.title = title
        self.keywords = keywords
    }
}

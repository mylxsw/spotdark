import Foundation

/// A tiny value type representing an application bundle discovered by Spotlight.
public struct IndexedApplication: Equatable, Hashable {
    public let bundleURL: URL

    public init(bundleURL: URL) {
        self.bundleURL = bundleURL
    }
}

public enum AppIndexDelta: Equatable {
    case initial([IndexedApplication])
    case update(added: [IndexedApplication], removed: [IndexedApplication])
}

/// Streams indexing updates.
public protocol AppIndexStreaming {
    /// Starts indexing and returns an async stream of deltas.
    func deltas() -> AsyncStream<AppIndexDelta>
}

import Foundation

/// A very small view model that owns the search state.
///
/// This is designed to be unit-testable without importing AppKit.
public final class LauncherViewModel {
    public private(set) var results: [SearchItem] = []

    private let engineProvider: () -> SearchEngine

    public init(engineProvider: @escaping () -> SearchEngine) {
        self.engineProvider = engineProvider
    }

    public func updateQuery(_ query: String) {
        results = engineProvider().search(query: query)
    }
}

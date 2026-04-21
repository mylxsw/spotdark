import Foundation
import SpotdarkCore

/// Persists simple usage signals for ranking.
///
/// Swift 6 Concurrency:
/// - `UsageScoring` is a nonisolated protocol used by `SearchEngine`.
/// - Therefore this type must NOT be `@MainActor`.
/// - We keep it thread-safe via a private lock.
final class UsageStore: UsageScoring {
    static let shared = UsageStore()

    private let defaults: UserDefaults
    private let key = "usage.app.open.count"
    private let lock = NSLock()

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordAppLaunch(bundleURL: URL) {
        lock.lock()
        defer { lock.unlock() }

        var dict = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        dict[bundleURL.path] = (dict[bundleURL.path] ?? 0) + 1
        defaults.set(dict, forKey: key)
    }

    func score(forAppBundleURL url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let dict = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        return dict[url.path] ?? 0
    }

    func score(forCommandID id: String) -> Int {
        0
    }
}

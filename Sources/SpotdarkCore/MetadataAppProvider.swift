import Foundation

/// A minimal interface to make Metadata-based indexing unit-testable.
public protocol MetadataQuerying {
    /// Returns application bundle URLs discovered by the query.
    func fetchApplicationBundleURLs() throws -> [URL]
}

/// Production implementation using NSMetadataQuery (Spotlight index).
///
/// This is closer to how Spotlight finds apps than directory scanning.
public final class SpotlightMetadataQuery: MetadataQuerying {
    public init() {}

    public func fetchApplicationBundleURLs() throws -> [URL] {
        // NSMetadataQuery is asynchronous; we block briefly for a starter implementation.
        // In production, you should make this async and stream results.
        let query = NSMetadataQuery()

        // Query all application bundles.
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")

        // Search the local computer scope.
        query.searchScopes = [NSMetadataQueryLocalComputerScope]

        let finished = DispatchSemaphore(value: 0)
        var urls: [URL] = []

        let nc = NotificationCenter.default
        let token = nc.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil) { _ in
            query.disableUpdates()
            query.stop()

            urls = (0 ..< query.resultCount).compactMap { idx in
                (query.result(at: idx) as? NSMetadataItem)?.value(forAttribute: kMDItemPath as String) as? String
            }.map { URL(fileURLWithPath: $0) }

            finished.signal()
        }

        query.start()

        // Wait up to 2 seconds for initial gathering.
        _ = finished.wait(timeout: .now() + 2)
        nc.removeObserver(token)

        return urls
    }
}

/// App provider backed by Spotlight metadata.
public final class MetadataAppProvider: AppProviding {
    private let query: MetadataQuerying

    public init(query: MetadataQuerying = SpotlightMetadataQuery()) {
        self.query = query
    }

    public func fetchApplications() throws -> [AppItem] {
        let urls = try query.fetchApplicationBundleURLs()
        var items: [AppItem] = []
        items.reserveCapacity(urls.count)

        for url in urls where url.pathExtension.lowercased() == "app" {
            let name = url.deletingPathExtension().lastPathComponent
            items.append(AppItem(name: name, bundleIdentifier: nil, bundleURL: url))
        }

        // Deduplicate and sort.
        let unique = Array(Set(items))
        return unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

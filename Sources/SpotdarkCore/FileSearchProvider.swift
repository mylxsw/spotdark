import Foundation

public protocol FileSearchProviding: Sendable {
    func search(query: String) -> AsyncStream<[FileItem]>
}

/// Searches for files on demand via NSMetadataQuery (Spotlight).
///
/// Each call to `search(query:)` creates a new query. The stream yields results once
/// gathering finishes, then terminates. Teardown happens on the main thread via
/// `onTermination` to satisfy NSMetadataQuery's threading requirements.
public final class SpotlightFileSearchProvider: FileSearchProviding {
    private let maxResults: Int

    public init(maxResults: Int = 20) {
        self.maxResults = maxResults
    }

    public func search(query: String) -> AsyncStream<[FileItem]> {
        let maxResults = self.maxResults
        return AsyncStream { continuation in
            // Wraps non-Sendable NSMetadataQuery so @Sendable closures can capture it safely.
            final class Handle: @unchecked Sendable {
                let query: NSMetadataQuery
                var finishToken: NSObjectProtocol?

                init(query: NSMetadataQuery) {
                    self.query = query
                }

                func stop() {
                    if let token = finishToken {
                        NotificationCenter.default.removeObserver(token)
                        finishToken = nil
                    }
                    query.stop()
                }
            }

            let mdQuery = NSMetadataQuery()
            // Exclude app bundles — those are handled by SpotlightIndexStream.
            mdQuery.predicate = NSPredicate(
                format: "%K CONTAINS[cd] %@ AND %K != 'com.apple.application-bundle'",
                NSMetadataItemFSNameKey,
                query,
                NSMetadataItemContentTypeKey
            )
            mdQuery.sortDescriptors = [
                NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)
            ]
            mdQuery.searchScopes = [NSMetadataQueryLocalComputerScope]

            let handle = Handle(query: mdQuery)

            handle.finishToken = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: mdQuery,
                queue: .main
            ) { _ in
                mdQuery.disableUpdates()

                var files: [FileItem] = []
                let count = min(mdQuery.resultCount, maxResults)
                for i in 0..<count {
                    guard let item = mdQuery.result(at: i) as? NSMetadataItem else { continue }
                    guard let pathStr = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                    let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                        ?? URL(fileURLWithPath: pathStr).deletingPathExtension().lastPathComponent
                    let contentType = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
                    let modDate = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date

                    files.append(FileItem(
                        name: name,
                        path: URL(fileURLWithPath: pathStr),
                        contentType: contentType,
                        modificationDate: modDate
                    ))
                }

                handle.stop()
                continuation.yield(files)
                continuation.finish()
            }

            mdQuery.start()

            continuation.onTermination = { @Sendable _ in
                DispatchQueue.main.async {
                    handle.stop()
                }
            }
        }
    }
}

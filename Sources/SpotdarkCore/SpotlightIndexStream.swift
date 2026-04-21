import Foundation

/// Streams application bundles from Spotlight (NSMetadataQuery).
///
/// Notes:
/// - This yields an `.initial` snapshot once gathering completes.
/// - Afterwards it yields `.update` deltas from `NSMetadataQueryDidUpdate`.
///
/// Swift 6 Concurrency:
/// - `AsyncStream.Continuation.onTermination` uses a `@Sendable` closure.
/// - `NSMetadataQuery` is not `Sendable`, so we must avoid capturing it directly.
public final class SpotlightIndexStream: AppIndexStreaming {
    public init() {}

    public func deltas() -> AsyncStream<AppIndexDelta> {
        AsyncStream { continuation in
            // Wrap non-Sendable objects so they can be safely captured by @Sendable closures.
            final class Handle: @unchecked Sendable {
                let query: NSMetadataQuery
                let notificationCenter: NotificationCenter
                var finishToken: NSObjectProtocol?
                var updateToken: NSObjectProtocol?

                init(query: NSMetadataQuery, notificationCenter: NotificationCenter) {
                    self.query = query
                    self.notificationCenter = notificationCenter
                }
            }

            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
            query.searchScopes = [NSMetadataQueryLocalComputerScope]

            let handle = Handle(query: query, notificationCenter: .default)

            func app(from item: NSMetadataItem) -> IndexedApplication? {
                guard let path = item.value(forAttribute: kMDItemPath as String) as? String else { return nil }
                let url = URL(fileURLWithPath: path)
                guard url.pathExtension.lowercased() == "app" else { return nil }
                return IndexedApplication(bundleURL: url)
            }

            func emitInitialSnapshot() {
                let apps: [IndexedApplication] = (0 ..< query.resultCount).compactMap { idx in
                    guard let item = query.result(at: idx) as? NSMetadataItem else { return nil }
                    return app(from: item)
                }
                continuation.yield(.initial(apps))
            }

            handle.finishToken = handle.notificationCenter.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                query.disableUpdates()
                emitInitialSnapshot()
                query.enableUpdates()
            }

            handle.updateToken = handle.notificationCenter.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { notification in
                // According to NSMetadataQuery docs, userInfo may include these keys.
                let addedItems = (notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
                let removedItems = (notification.userInfo?[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem]) ?? []

                let added = addedItems.compactMap { app(from: $0) }
                let removed = removedItems.compactMap { app(from: $0) }

                if !added.isEmpty || !removed.isEmpty {
                    continuation.yield(.update(added: added, removed: removed))
                }
            }

            query.start()

            continuation.onTermination = { @Sendable _ in
                // Ensure teardown happens on the main thread.
                DispatchQueue.main.async {
                    if let token = handle.finishToken {
                        handle.notificationCenter.removeObserver(token)
                    }
                    if let token = handle.updateToken {
                        handle.notificationCenter.removeObserver(token)
                    }
                    handle.query.stop()
                }
            }
        }
    }
}

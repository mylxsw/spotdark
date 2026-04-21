import Foundation
import SpotdarkCore

/// Rebuilds the app index from the directories configured in Settings.
final class SettingsAppIndexStream: AppIndexStreaming {
    private let settingsStore: SettingsStore
    private let notificationCenter: NotificationCenter
    private let fileManager: FileManager
    private let maxDepth: Int

    init(
        settingsStore: SettingsStore,
        notificationCenter: NotificationCenter = .default,
        fileManager: FileManager = .default,
        maxDepth: Int = 2
    ) {
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        self.fileManager = fileManager
        self.maxDepth = maxDepth
    }

    func deltas() -> AsyncStream<AppIndexDelta> {
        AsyncStream { continuation in
            let notificationCenter = self.notificationCenter

            final class StateBox: @unchecked Sendable {
                var observer: NSObjectProtocol?
                var latestRefreshID = 0
                var hasEmittedInitial = false
                var currentApps = Set<IndexedApplication>()
            }

            let state = StateBox()

            @Sendable
            func sortedApps(_ apps: Set<IndexedApplication>) -> [IndexedApplication] {
                apps.sorted {
                    $0.bundleURL.lastPathComponent.localizedCaseInsensitiveCompare($1.bundleURL.lastPathComponent) == .orderedAscending
                }
            }

            @Sendable
            func refresh(using directories: [URL]) {
                state.latestRefreshID += 1
                let refreshID = state.latestRefreshID

                Task.detached(priority: .utility) { [fileManager, maxDepth] in
                    let provider = DefaultAppProvider(
                        fileManager: fileManager,
                        appDirectories: directories,
                        maxDepth: maxDepth
                    )
                    let apps = (try? provider.fetchApplications()) ?? []
                    let nextApps = Set(apps.map { IndexedApplication(bundleURL: $0.bundleURL) })

                    await MainActor.run {
                        guard refreshID == state.latestRefreshID else { return }

                        if !state.hasEmittedInitial {
                            state.currentApps = nextApps
                            state.hasEmittedInitial = true
                            continuation.yield(.initial(sortedApps(nextApps)))
                            return
                        }

                        let added = nextApps.subtracting(state.currentApps)
                        let removed = state.currentApps.subtracting(nextApps)
                        state.currentApps = nextApps

                        if !added.isEmpty || !removed.isEmpty {
                            continuation.yield(
                                .update(
                                    added: sortedApps(added),
                                    removed: sortedApps(removed)
                                )
                            )
                        }
                    }
                }
            }

            state.observer = notificationCenter.addObserver(
                forName: SettingsStore.searchLocationsDidChangeNotification,
                object: settingsStore,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    refresh(using: self.settingsStore.searchLocationURLs)
                }
            }

            Task { @MainActor in
                refresh(using: self.settingsStore.searchLocationURLs)
            }

            continuation.onTermination = { @Sendable _ in
                if let observer = state.observer {
                    notificationCenter.removeObserver(observer)
                }
            }
        }
    }
}

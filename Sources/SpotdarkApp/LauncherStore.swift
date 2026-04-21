import AppKit
import SwiftUI
import SpotdarkCore

@Observable
@MainActor
final class LauncherStore {
    var query: String = "" {
        didSet { scheduleSearch() }
    }

    private(set) var results: [SearchItem] = []
    private(set) var trimmedQuery: String = ""
    private(set) var isInitialIndexing: Bool = true

    /// Selection index for the results list.
    ///
    /// IMPORTANT:
    /// Do not clamp via `didSet` by assigning to `selectedIndex` again.
    /// With Observation macros, that can trigger re-entrant writes and crash.
    var selectedIndex: Int = 0

    private let commandProvider: CommandProviding
    private var engine: SearchEngine?

    private let tasks = TaskBox()

    // Focus requests are bridged via a counter.
    private(set) var focusRequestID: Int = 0

    var isShowingResults: Bool {
        !results.isEmpty
    }

    var isShowingNoResultsState: Bool {
        !trimmedQuery.isEmpty && results.isEmpty
    }

    init(
        commandProvider: CommandProviding,
        indexStream: AppIndexStreaming = SpotlightIndexStream()
    ) {
        self.commandProvider = commandProvider

        startIndexing(stream: indexStream)
        rebuildEngine(apps: [])
    }

    deinit {
        tasks.cancelAll()
    }

    func requestFocus() {
        focusRequestID += 1
    }

    func select(index: Int) {
        selectedIndex = clampIndex(index)
    }

    func moveSelection(delta: Int) {
        guard !results.isEmpty else {
            selectedIndex = 0
            return
        }
        select(index: selectedIndex + delta)
    }

    func performSelectedAction() {
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        perform(item: results[selectedIndex])
    }

    func perform(item: SearchItem) {
        switch item {
        case .application(let app):
            UsageStore.shared.recordAppLaunch(bundleURL: app.bundleURL)
            NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: NSWorkspace.OpenConfiguration())
        case .command(let command):
            handle(command: command)
        }

        hide()
    }

    func hide() {
        LauncherCoordinator.shared.hide()
    }

    // MARK: - Indexing

    private var indexedAppsByURL: [URL: AppItem] = [:]

    private func startIndexing(stream: AppIndexStreaming) {
        tasks.setIndexTask(Task { [weak self] in
            guard let self else { return }
            for await delta in stream.deltas() {
                await MainActor.run {
                    self.apply(delta: delta)
                }
            }
        })
    }

    private func apply(delta: AppIndexDelta) {
        switch delta {
        case .initial(let apps):
            // The first Spotlight snapshot completes the initial loading phase.
            isInitialIndexing = false
            indexedAppsByURL = Dictionary(uniqueKeysWithValues: apps.map { app in
                let url = app.bundleURL
                let name = AppPresentationCache.shared.displayName(for: url)
                return (url, AppItem(name: name, bundleIdentifier: nil, bundleURL: url))
            })

        case .update(let added, let removed):
            for app in removed {
                indexedAppsByURL.removeValue(forKey: app.bundleURL)
            }
            for app in added {
                let url = app.bundleURL
                let name = AppPresentationCache.shared.displayName(for: url)
                indexedAppsByURL[url] = AppItem(name: name, bundleIdentifier: nil, bundleURL: url)
            }
        }

        rebuildEngine(apps: Array(indexedAppsByURL.values))
    }

    private func rebuildEngine(apps: [AppItem]) {
        let commands = commandProvider.allCommands()
        engine = SearchEngine(apps: apps, commands: commands, usage: UsageStore.shared)
        scheduleSearch(immediate: true)
    }

    // MARK: - Search

    private func scheduleSearch(immediate: Bool = false) {
        tasks.setSearchTask(Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms debounce
            }
            await MainActor.run {
                self.performSearchNow()
            }
        })
    }

    private func performSearchNow() {
        trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = engine?.search(query: trimmedQuery) ?? []
        selectedIndex = clampIndex(selectedIndex)
    }

    private func clampIndex(_ index: Int) -> Int {
        guard !results.isEmpty else { return 0 }
        return min(max(index, 0), results.count - 1)
    }

    private func handle(command: CommandItem) {
        switch command.id {
        case "open-settings":
            LauncherCoordinator.shared.showSettings()
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }
}

/// Stores Tasks in a nonisolated container to avoid Swift 6 actor-isolation issues in deinit.
private final class TaskBox {
    private let lock = NSLock()
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    func setIndexTask(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        indexTask?.cancel()
        indexTask = task
    }

    func setSearchTask(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        searchTask?.cancel()
        searchTask = task
    }

    func cancelAll() {
        lock.lock()
        defer { lock.unlock() }
        indexTask?.cancel()
        searchTask?.cancel()
        indexTask = nil
        searchTask = nil
    }
}

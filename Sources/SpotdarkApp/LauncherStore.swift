import AppKit
import SwiftUI
import SpotdarkCore

@Observable
@MainActor
final class LauncherStore {
    var query: String = "" {
        didSet {
            handlePresentationQueryChange(from: oldValue, to: query)
            scheduleSearch()
        }
    }

    private(set) var results: [SearchItem] = []
    private(set) var trimmedQuery: String = ""
    private(set) var isInitialIndexing: Bool = true
    private(set) var isSearchPending: Bool = false

    /// Selection index for the results list.
    ///
    /// IMPORTANT:
    /// Do not clamp via `didSet` by assigning to `selectedIndex` again.
    /// With Observation macros, that can trigger re-entrant writes and crash.
    var selectedIndex: Int = 0

    private let commandProvider: CommandProviding
    private let fileSearchProvider: FileSearchProviding
    private var engine: SearchEngine?

    private let tasks = TaskBox()
    private var lastPreferredPanelHeight = LauncherPanelMetrics.collapsedHeight

    // Focus requests are bridged via a counter.
    private(set) var focusRequestID: Int = 0
    var onPanelHeightChange: ((CGFloat, Bool) -> Void)?

    var isShowingResults: Bool {
        !results.isEmpty
    }

    var isShowingNoResultsState: Bool {
        isShowingExpandedContent && !isSearchPending && !isInitialIndexing && results.isEmpty
    }

    var isShowingExpandedContent: Bool {
        !liveTrimmedQuery.isEmpty
    }

    var preferredPanelHeight: CGFloat {
        isShowingExpandedContent ? LauncherPanelMetrics.expandedHeight : LauncherPanelMetrics.collapsedHeight
    }

    init(
        commandProvider: CommandProviding,
        indexStream: AppIndexStreaming = SpotlightIndexStream(),
        fileSearchProvider: FileSearchProviding = SpotlightFileSearchProvider()
    ) {
        self.commandProvider = commandProvider
        self.fileSearchProvider = fileSearchProvider

        startIndexing(stream: indexStream)
        rebuildEngine(apps: [])
    }

    deinit {
        tasks.cancelAll()
    }

    func requestFocus() {
        focusRequestID += 1
    }

    func prepareForPresentation() {
        tasks.cancelSearchTask()
        query = ""
        trimmedQuery = ""
        results = []
        isSearchPending = false
        selectedIndex = 0
        notifyPanelHeightChange(force: true, animated: false)
        requestFocus()
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
        case .file(let file):
            NSWorkspace.shared.open(file.path)
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
                try? await Task.sleep(nanoseconds: LauncherPanelMetrics.searchDebounceNanoseconds)
            }
            await MainActor.run {
                self.performSearchNow()
            }
        })
    }

    private func performSearchNow() {
        trimmedQuery = liveTrimmedQuery
        let appResults = engine?.search(query: trimmedQuery) ?? []
        results = appResults
        isSearchPending = false
        selectedIndex = clampIndex(selectedIndex)
        notifyPanelHeightChange(animated: true)

        // Run file search in parallel for queries with at least 2 characters.
        guard trimmedQuery.count >= 2 else {
            tasks.cancelFileSearchTask()
            return
        }

        let querySnapshot = trimmedQuery
        let provider = fileSearchProvider
        tasks.setFileSearchTask(Task { [weak self] in
            guard let self else { return }
            for await fileItems in provider.search(query: querySnapshot) {
                guard !Task.isCancelled else { return }
                let fileResults = fileItems.map { SearchItem.file($0) }
                let combined = Array((appResults + fileResults).prefix(20))
                await MainActor.run { [weak self] in
                    guard let self, self.trimmedQuery == querySnapshot else { return }
                    self.results = combined
                    self.selectedIndex = self.clampIndex(self.selectedIndex)
                }
            }
        })
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

    private var liveTrimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handlePresentationQueryChange(from oldValue: String, to newValue: String) {
        let oldTrimmedValue = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if newTrimmedValue.isEmpty {
            isSearchPending = false
        } else {
            isSearchPending = true
        }

        guard oldTrimmedValue.isEmpty != newTrimmedValue.isEmpty else { return }
        notifyPanelHeightChange(animated: true)
    }

    private func notifyPanelHeightChange(force: Bool = false, animated: Bool) {
        let preferredHeight = preferredPanelHeight
        guard force || lastPreferredPanelHeight != preferredHeight else { return }
        lastPreferredPanelHeight = preferredHeight
        onPanelHeightChange?(preferredHeight, animated)
    }
}

/// Stores Tasks in a nonisolated container to avoid Swift 6 actor-isolation issues in deinit.
private final class TaskBox {
    private let lock = NSLock()
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var fileSearchTask: Task<Void, Never>?

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

    func setFileSearchTask(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        fileSearchTask?.cancel()
        fileSearchTask = task
    }

    func cancelAll() {
        lock.lock()
        defer { lock.unlock() }
        indexTask?.cancel()
        searchTask?.cancel()
        fileSearchTask?.cancel()
        indexTask = nil
        searchTask = nil
        fileSearchTask = nil
    }

    func cancelSearchTask() {
        lock.lock()
        defer { lock.unlock() }
        searchTask?.cancel()
        fileSearchTask?.cancel()
        searchTask = nil
        fileSearchTask = nil
    }

    func cancelFileSearchTask() {
        lock.lock()
        defer { lock.unlock() }
        fileSearchTask?.cancel()
        fileSearchTask = nil
    }
}

import AppKit
import SwiftUI
import SpotdarkCore

@Observable
@MainActor
final class LauncherStore {
    var query: String = "" {
        didSet {
            handlePresentationQueryChange(from: oldValue, to: query)
            scheduleSearch(immediate: liveTrimmedQuery.isEmpty)
        }
    }

    private(set) var results: [SearchItem] = []
    private(set) var recentItems: [SearchItem] = []
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
    private let recentItemsProvider: @MainActor ([AppItem]) -> [SearchItem]
    private var engine: SearchEngine?
    private let calculator = ExpressionCalculator()

    private let tasks = TaskBox()
    private var lastPreferredPanelHeight = LauncherPanelMetrics.collapsedHeight

    // Focus requests are bridged via a counter.
    private(set) var focusRequestID: Int = 0
    var onPanelHeightChange: ((CGFloat, Bool) -> Void)?

    var isShowingResults: Bool {
        !displayedItems.isEmpty
    }

    var shouldShowLoadingState: Bool {
        isInitialIndexing && !isShowingResults
    }

    var isShowingRecentItems: Bool {
        false
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

    var displayedItems: [SearchItem] {
        let rankedResults = results.filter {
            if case .calculator = $0 { return false }
            return true
        }

        guard let calculatorItem = liveCalculatorItem else {
            return rankedResults
        }

        return [.calculator(calculatorItem)] + rankedResults
    }

    var displayedSections: [LauncherItemSection] {
        LauncherItemSectionBuilder.makeSections(
            items: displayedItems,
            isShowingRecentItems: isShowingRecentItems,
            pinnedIDs: PinnedItemsStore.shared.pinnedIDs
        )
    }

    init(
        commandProvider: CommandProviding,
        indexStream: AppIndexStreaming = SpotlightIndexStream(),
        fileSearchProvider: FileSearchProviding = SpotlightFileSearchProvider(),
        recentItemsProvider: @escaping @MainActor ([AppItem]) -> [SearchItem] = LauncherStore.defaultRecentItems
    ) {
        self.commandProvider = commandProvider
        self.fileSearchProvider = fileSearchProvider
        self.recentItemsProvider = recentItemsProvider

        startIndexing(stream: indexStream)
        rebuildEngine(apps: [])

        PluginManager.shared.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildEngine(apps: Array(self.indexedAppsByURL.values))
            }
        }
    }

    deinit {
        tasks.cancelAll()
    }

    func requestFocus() {
        focusRequestID += 1
    }

    func insertTextInput(_ text: String) {
        guard !text.isEmpty else { return }
        query += text
        requestFocus()
    }

    func prepareForPresentation() {
        tasks.cancelSearchTask()
        query = ""
        trimmedQuery = ""
        results = []
        refreshRecentItems()
        isSearchPending = false
        selectedIndex = 0
        notifyPanelHeightChange(force: true, animated: false)
        requestFocus()
    }

    func select(index: Int) {
        selectedIndex = clampIndex(index)
    }

    func moveSelection(delta: Int) {
        guard !displayedItems.isEmpty else {
            selectedIndex = 0
            return
        }

        // Navigate in visual (section) order so that up/down moves through items
        // top-to-bottom as rendered, not by raw flat-array position.
        let orderedRows = displayedSections.flatMap(\.rows)
        guard !orderedRows.isEmpty else {
            selectedIndex = 0
            return
        }

        let currentVisualIndex = orderedRows.firstIndex(where: { $0.index == selectedIndex }) ?? 0
        let newVisualIndex = min(max(currentVisualIndex + delta, 0), orderedRows.count - 1)
        selectedIndex = orderedRows[newVisualIndex].index
    }

    func performSelectedAction() {
        guard selectedIndex >= 0, selectedIndex < displayedItems.count else { return }
        perform(item: displayedItems[selectedIndex])
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
        case .calculator(let calc):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(calc.copyValue, forType: .string)
        case .webSearch(let webSearch):
            NSWorkspace.shared.open(webSearch.url)
        case .plugin(let pluginItem):
            PluginManager.shared.searchSource(for: pluginItem.pluginID)?.perform(item: pluginItem)
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
        let builtInCommands = commandProvider.allCommands()
        let pluginCommands = PluginManager.shared.actionPlugins().flatMap { $0.commands() }
        engine = SearchEngine(apps: apps, commands: builtInCommands + pluginCommands, usage: UsageStore.shared)
        refreshRecentItems()
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
        guard !trimmedQuery.isEmpty else {
            tasks.cancelFileSearchTask()
            refreshRecentItems()
            results = []
            isSearchPending = false
            selectedIndex = clampIndex(selectedIndex)
            notifyPanelHeightChange(animated: true)
            return
        }

        recentItems = []

        // Queries starting with "?" force a web search without running other providers.
        if trimmedQuery.hasPrefix("?") {
            let webQuery = trimmedQuery.dropFirst().trimmingCharacters(in: .whitespaces)
            tasks.cancelFileSearchTask()
            applySearchResults(webQuery.isEmpty ? [] : [makeWebSearchItem(query: webQuery)], resetSelection: true)
            isSearchPending = false
            notifyPanelHeightChange(animated: true)
            return
        }

        let appResults = engine?.search(query: trimmedQuery) ?? []
        let calcResult = calculator.evaluate(query: trimmedQuery).map { SearchItem.calculator($0) }
        let calcPrefix: [SearchItem] = calcResult.map { [$0] } ?? []
        let pluginResults = PluginManager.shared.searchSources()
            .flatMap { $0.search(query: trimmedQuery) }
            .sorted { $0.score < $1.score }
            .map { SearchItem.plugin($0.item) }
        let rankedBaseResults = rankedResults(appResults + pluginResults, query: trimmedQuery)
        let baseResults = calcPrefix + rankedBaseResults
        applySearchResults(baseResults.isEmpty ? [makeWebSearchItem(query: trimmedQuery)] : baseResults, resetSelection: true)
        isSearchPending = false
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
                let rankedResults = self.rankedResults(appResults + pluginResults + fileResults, query: querySnapshot)
                let combined = Array((calcPrefix + rankedResults).prefix(20))
                await MainActor.run { [weak self] in
                    guard let self, self.trimmedQuery == querySnapshot else { return }
                    self.applySearchResults(
                        combined.isEmpty ? [self.makeWebSearchItem(query: querySnapshot)] : combined,
                        resetSelection: false
                    )
                }
            }
        })
    }

    private func applySearchResults(_ newResults: [SearchItem], resetSelection: Bool) {
        let previouslySelectedItem = currentSelectedItem
        results = newResults

        guard !results.isEmpty else {
            selectedIndex = 0
            return
        }

        if resetSelection {
            selectedIndex = 0
            return
        }

        if let previouslySelectedItem,
           let preservedIndex = results.firstIndex(of: previouslySelectedItem) {
            selectedIndex = preservedIndex
            return
        }

        selectedIndex = clampIndex(selectedIndex)
    }

    private func makeWebSearchItem(query: String) -> SearchItem {
        let engine = SettingsStore.shared.selectedWebSearchEngine
        let url = engine.searchURL(for: query) ?? URL(string: "https://www.google.com")!
        return SearchItem.webSearch(WebSearchItem(query: query, engine: engine, url: url))
    }

    private func rankedResults(_ items: [SearchItem], query: String) -> [SearchItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return items }

        return items.enumerated()
            .sorted { lhs, rhs in
                let lhsScore = matchScore(for: lhs.element, query: normalizedQuery)
                let rhsScore = matchScore(for: rhs.element, query: normalizedQuery)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func matchScore(for item: SearchItem, query: String) -> Int {
        searchableTexts(for: item)
            .compactMap { textMatchScore($0, query: query) }
            .min() ?? 4
    }

    private func searchableTexts(for item: SearchItem) -> [String] {
        switch item {
        case .application(let app):
            return [app.name]
        case .command(let command):
            return [command.title] + command.keywords
        case .file(let file):
            return [file.name]
        case .plugin(let plugin):
            return [plugin.title, plugin.subtitle].compactMap { $0 }
        case .calculator(let calculator):
            return [calculator.displayResult]
        case .webSearch(let webSearch):
            return [webSearch.query]
        }
    }

    private func textMatchScore(_ text: String, query: String) -> Int? {
        let lowerText = text.lowercased()
        if lowerText.hasPrefix(query) { return 0 }
        if lowerText
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .dropFirst()
            .contains(where: { $0.hasPrefix(query) }) {
            return 1
        }
        if lowerText.contains(query) { return 2 }
        return nil
    }

    private func clampIndex(_ index: Int) -> Int {
        guard !displayedItems.isEmpty else { return 0 }
        return min(max(index, 0), displayedItems.count - 1)
    }

    private var currentSelectedItem: SearchItem? {
        guard selectedIndex >= 0, selectedIndex < displayedItems.count else { return nil }
        return displayedItems[selectedIndex]
    }

    private func handle(command: CommandItem) {
        switch command.id {
        case "open-settings":
            LauncherCoordinator.shared.showSettings()
        case "quit":
            NSApp.terminate(nil)
        default:
            PluginManager.shared.actionPlugin(for: command.id)?.handle(commandID: command.id)
        }
    }

    private var liveTrimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var liveCalculatorItem: CalculatorItem? {
        calculator.evaluate(query: liveTrimmedQuery)
    }

    private func refreshRecentItems() {
        recentItems = recentItemsProvider(Array(indexedAppsByURL.values))
    }

    private static func defaultRecentItems(from apps: [AppItem]) -> [SearchItem] {
        let recentApps = UsageStore.shared
            .recentApps(from: apps, limit: LauncherPanelMetrics.recentItemsLimit)
            .map(SearchItem.application)
        let recentFiles = Array(
            NSDocumentController.shared.recentDocumentURLs
            .prefix(LauncherPanelMetrics.recentItemsLimit)
            .map { url in
                SearchItem.file(
                    FileItem(
                        name: url.lastPathComponent,
                        path: url,
                        contentType: nil,
                        modificationDate: nil
                    )
                )
            }
        )

        var combined: [SearchItem] = []
        var appIterator = recentApps.makeIterator()
        var fileIterator = recentFiles.makeIterator()

        while combined.count < LauncherPanelMetrics.recentItemsLimit {
            var appendedItem = false

            if let app = appIterator.next() {
                combined.append(app)
                appendedItem = true
            }
            if combined.count == LauncherPanelMetrics.recentItemsLimit {
                break
            }
            if let file = fileIterator.next() {
                combined.append(file)
                appendedItem = true
            }
            if combined.count == LauncherPanelMetrics.recentItemsLimit {
                break
            }
            if !appendedItem {
                break
            }
        }

        return combined
    }

    private func handlePresentationQueryChange(from oldValue: String, to newValue: String) {
        let oldTrimmedValue = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if newTrimmedValue.isEmpty {
            isSearchPending = false
        } else {
            isSearchPending = true
            selectedIndex = 0
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

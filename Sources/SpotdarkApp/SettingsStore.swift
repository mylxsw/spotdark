import Foundation
import ServiceManagement
import SpotdarkCore

@MainActor
final class SettingsStore: ObservableObject {
    struct ShortcutFeedback: Equatable {
        enum Kind: Equatable {
            case info
            case success
            case warning
            case error
        }

        let kind: Kind
        let message: String
    }

    typealias HotKeyApplyAction = @MainActor (HotKey) -> Result<Void, HotKeyError>

    static let shared = SettingsStore()
    static let defaultLauncherHotKey: HotKey = .commandSpace

    private enum DefaultsKey {
        static let hotKeyCode = "settings.launcherHotKey.keyCode"
        static let hotKeyModifiers = "settings.launcherHotKey.modifiers"
        static let customSearchLocations = "settings.search.customLocations"
        static let selectedAppearance = "settings.appearance"
        static let showsMenuBarItem = "settings.showsMenuBarItem"
        static let remembersPanelPosition = "settings.remembersPanelPosition"
    }

    nonisolated static let searchLocationsDidChangeNotification = Notification.Name("SettingsStore.searchLocationsDidChange")

    @Published var selectedPane: SettingsPane
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            do {
                if launchAtLoginEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {}
        }
    }
    @Published var showsMenuBarItem: Bool {
        didSet {
            defaults?.set(showsMenuBarItem, forKey: DefaultsKey.showsMenuBarItem)
            applyShowsMenuBarItem?(showsMenuBarItem)
        }
    }
    @Published var selectedAppearance: SettingsAppearance {
        didSet {
            defaults?.set(selectedAppearance.rawValue, forKey: DefaultsKey.selectedAppearance)
            applyAppearance?(selectedAppearance)
        }
    }
    @Published var remembersPanelPosition: Bool {
        didSet {
            defaults?.set(remembersPanelPosition, forKey: DefaultsKey.remembersPanelPosition)
        }
    }
    @Published private(set) var launcherHotKey: HotKey
    @Published private(set) var isRecordingShortcut: Bool
    @Published private(set) var shortcutFeedback: ShortcutFeedback?
    @Published private(set) var defaultSearchLocations: [String]
    @Published private(set) var customSearchLocations: [String]
    @Published var selectedCustomSearchLocation: String?

    var applyLauncherHotKey: HotKeyApplyAction?
    var applyAppearance: (@MainActor (SettingsAppearance) -> Void)?
    var applyShowsMenuBarItem: (@MainActor (Bool) -> Void)?

    private let defaults: UserDefaults?

    init(
        selectedPane: SettingsPane = .general,
        launchAtLoginEnabled: Bool = false,
        showsMenuBarItem: Bool = true,
        selectedAppearance: SettingsAppearance = .followSystem,
        remembersPanelPosition: Bool = false,
        launcherHotKey: HotKey? = nil,
        isRecordingShortcut: Bool = false,
        shortcutFeedback: ShortcutFeedback? = nil,
        defaultSearchLocations: [String]? = nil,
        customSearchLocations: [String]? = nil,
        selectedCustomSearchLocation: String? = nil,
        defaults: UserDefaults? = .standard,
        applyLauncherHotKey: HotKeyApplyAction? = nil
    ) {
        self.defaults = defaults
        self.selectedPane = selectedPane
        self.showsMenuBarItem = defaults.flatMap { d -> Bool? in
            guard d.object(forKey: DefaultsKey.showsMenuBarItem) != nil else { return nil }
            return d.bool(forKey: DefaultsKey.showsMenuBarItem)
        } ?? showsMenuBarItem
        self.selectedAppearance = defaults
            .flatMap { $0.string(forKey: DefaultsKey.selectedAppearance) }
            .flatMap { SettingsAppearance(rawValue: $0) } ?? selectedAppearance
        self.remembersPanelPosition = defaults.flatMap { d -> Bool? in
            guard d.object(forKey: DefaultsKey.remembersPanelPosition) != nil else { return nil }
            return d.bool(forKey: DefaultsKey.remembersPanelPosition)
        } ?? remembersPanelPosition
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.launcherHotKey = Self.normalizedShortcut(
            defaults.flatMap(Self.restoreLauncherHotKey(from:)) ?? launcherHotKey ?? Self.defaultLauncherHotKey
        )
        self.isRecordingShortcut = isRecordingShortcut
        self.shortcutFeedback = shortcutFeedback
        let resolvedDefaultSearchLocations = (defaultSearchLocations ?? Self.defaultSearchLocationPaths())
            .map(Self.normalizedPath)
        self.defaultSearchLocations = resolvedDefaultSearchLocations
        let restoredCustomLocations = defaults.flatMap(Self.restoreCustomSearchLocations(from:)) ?? []
        self.customSearchLocations = Self.sanitizedCustomSearchLocations(
            customSearchLocations ?? restoredCustomLocations,
            defaultPaths: resolvedDefaultSearchLocations
        )
        self.selectedCustomSearchLocation = selectedCustomSearchLocation.flatMap { candidate in
            let normalized = Self.normalizedPath(candidate)
            return self.customSearchLocations.contains(normalized) ? normalized : nil
        }
        self.applyLauncherHotKey = applyLauncherHotKey
    }

    var currentShortcutDisplay: String {
        launcherHotKey.displayString
    }

    var fallbackShortcutDisplay: String {
        Self.defaultLauncherHotKey.displayString
    }

    var canResetShortcut: Bool {
        launcherHotKey != Self.defaultLauncherHotKey
    }

    var shortcutPrimaryButtonTitle: String {
        isRecordingShortcut ? SettingsStrings.cancelShortcutRecordingButton : SettingsStrings.recordShortcutButton
    }

    var searchLocationURLs: [URL] {
        (defaultSearchLocations + customSearchLocations).map(Self.url(fromPath:))
    }

    var canRemoveSelectedCustomSearchLocation: Bool {
        selectedCustomSearchLocation != nil
    }

    var canMoveSelectedCustomSearchLocationUp: Bool {
        guard let selectedCustomSearchLocation,
              let index = customSearchLocations.firstIndex(of: selectedCustomSearchLocation) else {
            return false
        }

        return index > 0
    }

    var canMoveSelectedCustomSearchLocationDown: Bool {
        guard let selectedCustomSearchLocation,
              let index = customSearchLocations.firstIndex(of: selectedCustomSearchLocation) else {
            return false
        }

        return index < customSearchLocations.count - 1
    }

    func syncLaunchAtLoginFromOS() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func beginShortcutRecording() {
        isRecordingShortcut = true
        shortcutFeedback = ShortcutFeedback(
            kind: .info,
            message: SettingsStrings.shortcutRecordingActiveMessage
        )
    }

    func cancelShortcutRecording() {
        isRecordingShortcut = false
        shortcutFeedback = ShortcutFeedback(
            kind: .info,
            message: SettingsStrings.shortcutRecordingCancelledMessage
        )
    }

    func toggleShortcutRecording() {
        isRecordingShortcut ? cancelShortcutRecording() : beginShortcutRecording()
    }

    func applyRecordedShortcut(_ hotKey: HotKey) {
        if let message = Self.validationMessage(for: hotKey) {
            shortcutFeedback = ShortcutFeedback(kind: .warning, message: message)
        } else {
            applyShortcut(hotKey, successMessage: SettingsStrings.shortcutUpdatedMessage)
        }
    }

    func resetShortcutToDefault() {
        guard canResetShortcut else { return }
        isRecordingShortcut = false
        applyShortcut(Self.defaultLauncherHotKey, successMessage: SettingsStrings.shortcutResetMessage)
    }

    func clearShortcutFeedback() {
        shortcutFeedback = nil
    }

    func addCustomSearchLocation(_ url: URL) {
        let normalizedPath = Self.normalizedPath(url.path)
        guard !defaultSearchLocations.contains(normalizedPath) else { return }

        if customSearchLocations.contains(normalizedPath) {
            selectedCustomSearchLocation = normalizedPath
            return
        }

        customSearchLocations.append(normalizedPath)
        selectedCustomSearchLocation = normalizedPath
        persistCustomSearchLocations()
        notifySearchLocationsChanged()
    }

    func removeSelectedCustomSearchLocation() {
        guard let selectedCustomSearchLocation,
              let index = customSearchLocations.firstIndex(of: selectedCustomSearchLocation) else {
            return
        }

        customSearchLocations.remove(at: index)
        self.selectedCustomSearchLocation = customSearchLocations.indices.contains(index)
            ? customSearchLocations[index]
            : customSearchLocations.last
        persistCustomSearchLocations()
        notifySearchLocationsChanged()
    }

    func moveSelectedCustomSearchLocationUp() {
        moveSelectedCustomSearchLocation(by: -1)
    }

    func moveSelectedCustomSearchLocationDown() {
        moveSelectedCustomSearchLocation(by: 1)
    }

    // MARK: - Private

    private func applyShortcut(_ hotKey: HotKey, successMessage: String) {
        switch applyLauncherHotKey?(hotKey) ?? .success(()) {
        case .success:
            launcherHotKey = hotKey
            isRecordingShortcut = false
            persistLauncherHotKey(hotKey)
            shortcutFeedback = ShortcutFeedback(kind: .success, message: successMessage)
        case .failure(let error):
            isRecordingShortcut = false
            shortcutFeedback = ShortcutFeedback(
                kind: .error,
                message: Self.feedbackMessage(for: error)
            )
        }
    }

    private func persistLauncherHotKey(_ hotKey: HotKey) {
        defaults?.set(Int(hotKey.keyCode), forKey: DefaultsKey.hotKeyCode)
        defaults?.set(Int(hotKey.modifiers.rawValue), forKey: DefaultsKey.hotKeyModifiers)
    }

    private func persistCustomSearchLocations() {
        defaults?.set(customSearchLocations, forKey: DefaultsKey.customSearchLocations)
    }

    private func notifySearchLocationsChanged() {
        NotificationCenter.default.post(
            name: Self.searchLocationsDidChangeNotification,
            object: self
        )
    }

    private func moveSelectedCustomSearchLocation(by delta: Int) {
        guard let selectedCustomSearchLocation,
              let index = customSearchLocations.firstIndex(of: selectedCustomSearchLocation) else {
            return
        }

        let destination = index + delta
        guard customSearchLocations.indices.contains(destination) else { return }

        customSearchLocations.swapAt(index, destination)
        self.selectedCustomSearchLocation = customSearchLocations[destination]
        persistCustomSearchLocations()
        notifySearchLocationsChanged()
    }

    private static func restoreLauncherHotKey(from defaults: UserDefaults) -> HotKey? {
        guard defaults.object(forKey: DefaultsKey.hotKeyCode) != nil,
              defaults.object(forKey: DefaultsKey.hotKeyModifiers) != nil else {
            return nil
        }

        let keyCode = defaults.integer(forKey: DefaultsKey.hotKeyCode)
        let modifiers = defaults.integer(forKey: DefaultsKey.hotKeyModifiers)
        guard let keyCode = UInt16(exactly: keyCode),
              let modifiers = UInt(exactly: modifiers) else {
            return nil
        }

        return HotKey(keyCode: keyCode, modifiers: HotKeyModifierFlags(rawValue: modifiers))
    }

    private static func restoreCustomSearchLocations(from defaults: UserDefaults) -> [String]? {
        defaults.stringArray(forKey: DefaultsKey.customSearchLocations)
    }

    private static func normalizedShortcut(_ hotKey: HotKey) -> HotKey {
        validationMessage(for: hotKey) == nil ? hotKey : defaultLauncherHotKey
    }

    private static func validationMessage(for shortcut: HotKey) -> String? {
        let primaryModifiers = shortcut.modifiers.intersection([.command, .option, .control])
        guard !primaryModifiers.isEmpty else {
            return SettingsStrings.shortcutValidationModifierRequired
        }

        if reservedShortcuts.contains(shortcut) {
            return String(
                format: SettingsStrings.shortcutValidationReservedTemplate,
                shortcut.displayString
            )
        }

        return nil
    }

    private static func feedbackMessage(for error: HotKeyError) -> String {
        switch error {
        case .accessibilityPermissionRequired:
            SettingsStrings.shortcutPermissionFeedback
        case .monitorRegistrationFailed:
            SettingsStrings.shortcutRegistrationFailedFeedback
        }
    }

    private static let reservedShortcuts: Set<HotKey> = [
        HotKey(keyCode: 48, modifiers: .command)   // Cmd+Tab — always owned by the system
    ]

    private static func defaultSearchLocationPaths(fileManager: FileManager = .default) -> [String] {
        DefaultAppProvider.defaultApplicationDirectories(fileManager: fileManager)
            .map { normalizedPath($0.path) }
    }

    private static func sanitizedCustomSearchLocations(_ paths: [String], defaultPaths: [String]) -> [String] {
        var seen = Set<String>()

        return paths.map(normalizedPath).filter { path in
            guard !defaultPaths.contains(path) else { return false }
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
            .standardizedFileURL
            .path
    }

    private static func url(fromPath path: String) -> URL {
        URL(fileURLWithPath: normalizedPath(path), isDirectory: true)
    }

    static var preview: SettingsStore {
        SettingsStore(
            selectedPane: .search,
            selectedAppearance: .followSystem,
            launcherHotKey: HotKey(keyCode: 17, modifiers: [.command, .option]),
            shortcutFeedback: ShortcutFeedback(
                kind: .info,
                message: SettingsStrings.shortcutReadyMessage
            ),
            customSearchLocations: [
                "~/Developer/Applications",
                "~/Applications/Setapp"
            ],
            selectedCustomSearchLocation: NSString(string: "~/Developer/Applications").expandingTildeInPath,
            defaults: nil
        )
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case search
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            SettingsStrings.generalTabTitle
        case .shortcuts:
            SettingsStrings.shortcutsTabTitle
        case .search:
            SettingsStrings.searchTabTitle
        case .about:
            SettingsStrings.aboutTabTitle
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .shortcuts:
            "command"
        case .search:
            "magnifyingglass"
        case .about:
            "sparkles"
        }
    }
}

enum SettingsAppearance: String, CaseIterable, Identifiable {
    case followSystem
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .followSystem:
            SettingsStrings.systemAppearance
        case .light:
            SettingsStrings.lightAppearance
        case .dark:
            SettingsStrings.darkAppearance
        }
    }
}

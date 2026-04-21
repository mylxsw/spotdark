import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView(selection: $store.selectedPane) {
            GeneralSettingsPane(store: store)
                .tabItem {
                    Label(SettingsPane.general.title, systemImage: SettingsPane.general.systemImage)
                }
                .tag(SettingsPane.general)

            ShortcutSettingsPane(store: store)
                .tabItem {
                    Label(SettingsPane.shortcuts.title, systemImage: SettingsPane.shortcuts.systemImage)
                }
                .tag(SettingsPane.shortcuts)

            SearchSettingsPane(store: store)
                .tabItem {
                    Label(SettingsPane.search.title, systemImage: SettingsPane.search.systemImage)
                }
                .tag(SettingsPane.search)

            AboutSettingsPane()
                .tabItem {
                    Label(SettingsPane.about.title, systemImage: SettingsPane.about.systemImage)
                }
                .tag(SettingsPane.about)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            SettingsIntroSection(
                title: SettingsStrings.generalIntroTitle,
                message: SettingsStrings.generalIntroMessage
            )

            Section(SettingsStrings.appearanceSectionTitle) {
                Picker(SettingsStrings.appearancePickerTitle, selection: $store.selectedAppearance) {
                    ForEach(SettingsAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .disabled(true)

                SettingsSecondaryText(SettingsStrings.appearanceHelp)
            }

            Section(SettingsStrings.panelSectionTitle) {
                Toggle(SettingsStrings.launchAtLoginTitle, isOn: $store.launchAtLoginEnabled)
                    .disabled(true)
                SettingsSecondaryText(SettingsStrings.launchAtLoginHelp)

                Toggle(SettingsStrings.menuBarTitle, isOn: $store.showsMenuBarItem)
                    .disabled(true)
                SettingsSecondaryText(SettingsStrings.menuBarHelp)

                Toggle(SettingsStrings.panelPositionTitle, isOn: $store.remembersPanelPosition)
                    .disabled(true)
                SettingsSecondaryText(SettingsStrings.panelPositionHelp)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct ShortcutSettingsPane: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            SettingsIntroSection(
                title: SettingsStrings.shortcutsIntroTitle,
                message: SettingsStrings.shortcutsIntroMessage
            )

            Section {
                SettingsShortcutRecorderView(store: store)

                HStack {
                    Button(store.shortcutPrimaryButtonTitle) {
                        store.toggleShortcutRecording()
                    }

                    Button(SettingsStrings.resetShortcutButton) {
                        store.resetShortcutToDefault()
                    }
                    .disabled(!store.canResetShortcut || store.isRecordingShortcut)
                }

                if let feedback = store.shortcutFeedback {
                    SettingsShortcutFeedbackView(feedback: feedback)
                }

                SettingsSecondaryText(SettingsStrings.shortcutRecordingHelp)
            }

            Section {
                SettingsValueRow(
                    title: SettingsStrings.fallbackShortcutTitle,
                    value: store.fallbackShortcutDisplay
                )
                SettingsValueRow(
                    title: SettingsStrings.conflictHandlingTitle,
                    value: SettingsStrings.conflictHandlingValue
                )
                SettingsValueRow(
                    title: SettingsStrings.shortcutLiveUpdateTitle,
                    value: SettingsStrings.shortcutLiveUpdateValue
                )
                SettingsInlineNote(
                    title: SettingsStrings.shortcutRulesTitle,
                    message: SettingsStrings.shortcutRulesMessage
                )
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct SearchSettingsPane: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            SettingsIntroSection(
                title: SettingsStrings.searchIntroTitle,
                message: SettingsStrings.searchIntroMessage
            )

            Section(SettingsStrings.defaultLocationsSectionTitle) {
                ForEach(store.defaultSearchLocations, id: \.self) { location in
                    SettingsPathRow(path: location)
                }
                SettingsSecondaryText(SettingsStrings.defaultLocationsHelp)
            }

            Section(SettingsStrings.customLocationsSectionTitle) {
                if store.customSearchLocations.isEmpty {
                    SettingsEmptyState(
                        title: SettingsStrings.customLocationsEmptyTitle,
                        message: SettingsStrings.customLocationsEmptyMessage
                    )
                } else {
                    List(selection: $store.selectedCustomSearchLocation) {
                        ForEach(store.customSearchLocations, id: \.self) { location in
                            SettingsPathRow(path: location)
                                .tag(location)
                        }
                    }
                    .frame(minHeight: 168)
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }

                HStack {
                    Button(SettingsStrings.addFolderButton) {
                        presentFolderPicker()
                    }
                    Button(SettingsStrings.removeFolderButton) {
                        store.removeSelectedCustomSearchLocation()
                    }
                    .disabled(!store.canRemoveSelectedCustomSearchLocation)
                    Button(SettingsStrings.moveFolderUpButton) {
                        store.moveSelectedCustomSearchLocationUp()
                    }
                    .disabled(!store.canMoveSelectedCustomSearchLocationUp)
                    Button(SettingsStrings.moveFolderDownButton) {
                        store.moveSelectedCustomSearchLocationDown()
                    }
                    .disabled(!store.canMoveSelectedCustomSearchLocationDown)
                }

                SettingsSecondaryText(SettingsStrings.customLocationsHelp)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func presentFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = SettingsStrings.folderPickerTitle
        panel.message = SettingsStrings.folderPickerMessage
        panel.prompt = SettingsStrings.folderPickerPrompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addCustomSearchLocation(url)
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section(SettingsStrings.aboutSectionTitle) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(SettingsStrings.aboutHeadline)
                        .font(.title3.weight(.semibold))
                    Text(SettingsStrings.aboutSummary)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section(SettingsStrings.roadmapSectionTitle) {
                SettingsRoadmapRow(
                    title: SettingsStrings.roadmapShortcutTitle,
                    summary: SettingsStrings.roadmapShortcutSummary
                )
                SettingsRoadmapRow(
                    title: SettingsStrings.roadmapSearchTitle,
                    summary: SettingsStrings.roadmapSearchSummary
                )
                SettingsRoadmapRow(
                    title: SettingsStrings.roadmapFeedbackTitle,
                    summary: SettingsStrings.roadmapFeedbackSummary
                )
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct SettingsIntroSection: View {
    let title: String
    let message: String

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "sidebar.leading")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SettingsSecondaryText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
        }
    }
}

private struct SettingsPathRow: View {
    let path: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(NSString(string: path).abbreviatingWithTildeInPath)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsRoadmapRow: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(summary)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsInlineNote: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview("Settings") {
    SettingsView(store: .preview)
}

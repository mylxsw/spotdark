import AppKit
import SwiftUI
import SpotdarkCore

struct LauncherRootView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ZStack(alignment: .top) {
            // Base glass material.
            RoundedRectangle(cornerRadius: LauncherPanelMetrics.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: LauncherPanelMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )

            VStack(spacing: store.isShowingExpandedContent ? LauncherPanelMetrics.contentSpacing : 0) {
                searchBar
                if store.isShowingExpandedContent {
                    resultsList
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.995, anchor: .top))
                            )
                        )
                }
            }
            .padding(LauncherPanelMetrics.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: LauncherPanelMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: LauncherPanelMetrics.cornerRadius, style: .continuous))
        // Global keyboard behavior:
        // - Up/Down: navigate results
        // - Return: open selected item
        // - Esc: close
        .onMoveCommand { direction in
            switch direction {
            case .down:
                store.moveSelection(delta: 1)
            case .up:
                store.moveSelection(delta: -1)
            default:
                break
            }
        }
        .background(defaultActionButton)
        .onExitCommand {
            store.hide()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            LauncherSearchField(
                text: $store.query,
                placeholder: LauncherStrings.searchPlaceholder,
                focusRequestID: store.focusRequestID,
                onMoveSelection: { delta in
                    store.moveSelection(delta: delta)
                },
                onSubmit: {
                    store.performSelectedAction()
                },
                onExit: {
                    store.hide()
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            LauncherShortcutHintView(settingsStore: SettingsStore.shared)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(height: LauncherPanelMetrics.searchFieldHeight)
        .background(
            RoundedRectangle(cornerRadius: LauncherPanelMetrics.searchFieldCornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: LauncherPanelMetrics.searchFieldCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var defaultActionButton: some View {
        Button(action: {
            store.performSelectedAction()
        }) {
            EmptyView()
        }
        .keyboardShortcut(.defaultAction)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var resultsList: some View {
        Group {
            if store.isInitialIndexing {
                LauncherLoadingStateView()
                    .transition(.opacity)
            } else if store.isShowingResults {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(store.results.enumerated()), id: \.offset) { index, item in
                                Button {
                                    store.select(index: index)
                                    store.performSelectedAction()
                                } label: {
                                    LauncherRowView(item: item, query: store.trimmedQuery)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(rowBackground(isSelected: store.selectedIndex == index))
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .background(Color.clear)
                    .onChange(of: store.selectedIndex) {
                        withAnimation(.snappy(duration: LauncherPanelMetrics.selectionScrollAnimationDuration, extraBounce: 0)) {
                            proxy.scrollTo(store.selectedIndex, anchor: .center)
                        }
                    }
                }
                .transition(.opacity)
            } else if store.isShowingNoResultsState {
                LauncherEmptyStateView(
                    systemImage: "exclamationmark.magnifyingglass",
                    title: LauncherStrings.noResultsTitle,
                    message: String(
                        format: LauncherStrings.noResultsMessageTemplate,
                        store.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    ),
                    hint: LauncherStrings.noResultsHint
                )
                .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: LauncherPanelMetrics.expandedContentAnimationDuration, extraBounce: 0), value: store.isInitialIndexing)
        .animation(.snappy(duration: LauncherPanelMetrics.contentSwapAnimationDuration, extraBounce: 0), value: store.isShowingResults)
        .animation(.snappy(duration: LauncherPanelMetrics.contentSwapAnimationDuration, extraBounce: 0), value: store.isShowingNoResultsState)
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
        } else {
            Color.clear
        }
    }
}

struct LauncherRowView: View {
    let item: SearchItem
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(SearchHighlight.highlight(text: title, query: query))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var title: String {
        switch item {
        case .application(let app):
            return app.name
        case .command(let cmd):
            return cmd.title
        case .file(let file):
            return file.name
        }
    }

    private var subtitle: String {
        switch item {
        case .application:
            return LauncherStrings.applicationResultLabel
        case .command:
            return LauncherStrings.commandResultLabel
        case .file(let file):
            let parent = file.path.deletingLastPathComponent().path
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if parent.hasPrefix(home) {
                return "~" + parent.dropFirst(home.count)
            }
            return parent
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .application(let app):
            AppIconView(bundleURL: app.bundleURL)
        case .command:
            Image(systemName: "command")
                .resizable()
                .scaledToFit()
                .padding(5)
                .foregroundStyle(.secondary)
                .background(.thinMaterial)
        case .file(let file):
            Image(nsImage: AppPresentationCache.shared.fileIcon(for: file.path, size: CGSize(width: 28, height: 28)))
                .resizable()
                .scaledToFit()
        }
    }
}

import AppKit
import SwiftUI
import SpotdarkCore

struct LauncherRootView: View {
    @Bindable var store: LauncherStore

    @FocusState private var isSearchFocused: Bool

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
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
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
        .onChange(of: store.focusRequestID) {
            // Focus is requested by the panel controller when shown.
            isSearchFocused = true
        }
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
            isSearchFocused = true
        }
        .background(defaultActionButton)
        .onExitCommand {
            store.hide()
        }
        .onAppear {
            // Make sure the list does not steal focus.
            isSearchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(LauncherStrings.searchPlaceholder, text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold, design: .default))
                .focused($isSearchFocused)
                .onSubmit {
                    store.performSelectedAction()
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
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
                        withAnimation(.easeOut(duration: 0.12)) {
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
        .animation(.easeOut(duration: 0.2), value: store.isInitialIndexing)
        .animation(.easeOut(duration: 0.16), value: store.isShowingResults)
        .animation(.easeOut(duration: 0.16), value: store.isShowingNoResultsState)
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
        }
    }

    private var subtitle: String {
        switch item {
        case .application:
            return LauncherStrings.applicationResultLabel
        case .command:
            return LauncherStrings.commandResultLabel
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
        }
    }
}

struct AppIconView: NSViewRepresentable {
    let bundleURL: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = AppPresentationCache.shared.icon(for: bundleURL, size: CGSize(width: 28, height: 28))
    }
}

import AppKit
import SwiftUI
import SpotdarkCore

struct LauncherRootView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ZStack {
            panelBackground

            panelContent
        }
        .frame(width: LauncherPanelMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: LauncherPanelMetrics.cornerRadius, style: .continuous))
        .tint(LauncherGlassStyle.accent)
        .background(defaultActionButton)
        .onExitCommand {
            store.hide()
        }
    }

    private var panelBackground: some View {
        LauncherGlassBackground(cornerRadius: LauncherPanelMetrics.cornerRadius)
    }

    @ViewBuilder
    private var panelContent: some View {
        VStack(spacing: 0) {
            searchBar
                .frame(height: store.isShowingExpandedContent ? LauncherPanelMetrics.searchFieldHeight : LauncherPanelMetrics.collapsedHeight)

            if store.isShowingExpandedContent {
                Rectangle()
                    .fill(LauncherGlassStyle.divider)
                    .frame(height: 1)
                    .transition(.opacity.combined(with: .offset(y: -3)))

                bodyContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.launcherExpandedContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: LauncherPanelMetrics.expandedContentAnimationDuration, extraBounce: 0), value: store.isShowingExpandedContent)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LauncherGlassStyle.searchPlaceholder)

            LauncherSearchField(
                text: $store.query,
                placeholder: LauncherStrings.searchPlaceholder,
                textColor: NSColor(LauncherGlassStyle.searchText),
                placeholderColor: NSColor(LauncherGlassStyle.searchPlaceholder),
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
            .frame(height: 26)

            LauncherShortcutHintView(settingsStore: SettingsStore.shared)
        }
        .padding(.horizontal, LauncherPanelMetrics.searchBarHorizontalPadding)
        .padding(.top, LauncherPanelMetrics.searchBarTopPadding)
        .padding(.bottom, LauncherPanelMetrics.searchBarBottomPadding)
        .frame(height: LauncherPanelMetrics.searchFieldHeight)
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
                expandedFallback(content: AnyView(LauncherLoadingStateView()))
            } else if store.isShowingResults {
                LauncherItemListView(
                    sections: store.displayedSections,
                    query: store.trimmedQuery,
                    selectedIndex: store.selectedIndex,
                    onSelect: { index in
                        store.select(index: index)
                    },
                    onActivate: { _ in
                        store.performSelectedAction()
                    }
                )
                .transition(.launcherContentSwap)
            } else if store.isShowingNoResultsState {
                expandedFallback(
                    content: AnyView(
                        LauncherEmptyStateView(
                            systemImage: "exclamationmark.magnifyingglass",
                            title: LauncherStrings.noResultsTitle,
                            message: String(
                                format: LauncherStrings.noResultsMessageTemplate,
                                store.query.trimmingCharacters(in: .whitespacesAndNewlines)
                            ),
                            hint: LauncherStrings.noResultsHint
                        )
                    )
                )
                .transition(.launcherContentSwap)
            } else {
                Color.clear
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: LauncherPanelMetrics.expandedContentAnimationDuration, extraBounce: 0), value: store.isInitialIndexing)
        .animation(.snappy(duration: LauncherPanelMetrics.contentSwapAnimationDuration, extraBounce: 0), value: store.isShowingResults)
        .animation(.snappy(duration: LauncherPanelMetrics.contentSwapAnimationDuration, extraBounce: 0), value: store.isShowingNoResultsState)
    }

    private func expandedFallback(content: AnyView) -> some View {
        VStack {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if store.isShowingExpandedContent {
            resultsList
        } else {
            Color.clear
                .allowsHitTesting(false)
        }
    }
}

private extension AnyTransition {
    static var launcherExpandedContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -10)),
            removal: .opacity.combined(with: .offset(y: -4))
        )
    }

    static var launcherContentSwap: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .offset(y: -4))
        )
    }
}

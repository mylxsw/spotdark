import AppKit
import SwiftUI
import SpotdarkCore

struct LauncherItemListView: View {
    let sections: [LauncherItemSection]
    let query: String
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void

    @AccessibilityFocusState private var accessibilityFocusedRowIndex: Int?
    @State private var hoveredRowIndex: Int?
    private var pinnedStore: PinnedItemsStore { PinnedItemsStore.shared }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(sections) { section in
                        if let title = section.title {
                            LauncherSectionHeaderView(title: title)
                                .padding(.horizontal, 10)
                                .padding(.top, 1)
                                .padding(.bottom, 3)
                        }

                        ForEach(section.rows) { row in
                            Button {
                                onSelect(row.index)
                                onActivate(row.index)
                            } label: {
                                LauncherRowView(
                                    item: row.item,
                                    query: query,
                                    isSelected: selectedIndex == row.index,
                                    isPinned: pinnedStore.isPinned(row.item)
                                )
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        rowBackground(
                                            isSelected: selectedIndex == row.index,
                                            isHovered: hoveredRowIndex == row.index
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                            .id(row.index)
                            .transition(.launcherResultRow)
                            .accessibilityFocused($accessibilityFocusedRowIndex, equals: row.index)
                            .onHover { isHovered in
                                hoveredRowIndex = isHovered ? row.index : (hoveredRowIndex == row.index ? nil : hoveredRowIndex)
                            }
                            .contextMenu {
                                if stableID(for: row.item) != nil {
                                    if pinnedStore.isPinned(row.item) {
                                        Button(LauncherStrings.unpinItemLabel) {
                                            pinnedStore.unpin(row.item)
                                        }
                                    } else {
                                        Button(LauncherStrings.pinItemLabel) {
                                            pinnedStore.pin(row.item)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, LauncherPanelMetrics.resultsHorizontalPadding)
                .padding(.top, LauncherPanelMetrics.resultsTopPadding)
                .padding(.bottom, LauncherPanelMetrics.resultsBottomPadding)
                .animation(.smooth(duration: LauncherPanelMetrics.resultRowAnimationDuration, extraBounce: 0), value: sections)
            }
            .background(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(listAccessibilityLabel)
            .onChange(of: selectedIndex) {
                withAnimation(.snappy(duration: LauncherPanelMetrics.selectionScrollAnimationDuration, extraBounce: 0)) {
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
                syncAccessibilityFocus()
            }
            .onAppear(perform: syncAccessibilityFocus)
            .onChange(of: sections, syncAccessibilityFocus)
        }
    }

    private var listAccessibilityLabel: String {
        sections.contains { $0.kind == .recent }
            ? LauncherStrings.recentItemsAccessibilityLabel
            : LauncherStrings.searchResultsAccessibilityLabel
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: LauncherPanelMetrics.rowCornerRadius, style: .continuous)
                .fill(LauncherGlassStyle.selectionFill)
                .overlay(
                    RoundedRectangle(cornerRadius: LauncherPanelMetrics.rowCornerRadius, style: .continuous)
                        .strokeBorder(LauncherGlassStyle.selectionStroke, lineWidth: 1)
                )
        } else if isHovered {
            RoundedRectangle(cornerRadius: LauncherPanelMetrics.rowCornerRadius, style: .continuous)
                .fill(LauncherGlassStyle.hoverFill)
        } else {
            Color.clear
        }
    }

    private func syncAccessibilityFocus() {
        let rowIndices = sections.flatMap(\.rows).map(\.index)
        guard !rowIndices.isEmpty else {
            accessibilityFocusedRowIndex = nil
            return
        }

        accessibilityFocusedRowIndex = rowIndices.contains(selectedIndex) ? selectedIndex : rowIndices[0]
    }
}

private extension AnyTransition {
    static var launcherResultRow: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 5)),
            removal: .opacity
        )
    }
}

private struct LauncherSectionHeaderView: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LauncherGlassStyle.tertiary)
                .textCase(.uppercase)
                .tracking(0.9)

            Spacer(minLength: 0)
        }
    }
}

struct LauncherRowView: View {
    let item: SearchItem
    let query: String
    let isSelected: Bool
    var isPinned: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: LauncherPanelMetrics.rowIconSize, height: LauncherPanelMetrics.rowIconSize)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    SearchHighlight.highlight(
                        text: title,
                        query: query,
                        color: isSelected ? LauncherGlassStyle.selectedHighlight : LauncherGlassStyle.selectionFill
                    )
                )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : LauncherGlassStyle.title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.88) : LauncherGlassStyle.tertiary)
                        .rotationEffect(.degrees(45))
                }

                if isSelected {
                    Text("↩")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.16))
                        )
                }
            }
        }
        .frame(minHeight: LauncherPanelMetrics.rowMinHeight - 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: String {
        switch item {
        case .application(let app):
            return app.name
        case .command(let cmd):
            return cmd.title
        case .file(let file):
            return file.name
        case .calculator(let calc):
            return calc.displayResult
        case .webSearch(let ws):
            return String(format: LauncherStrings.webSearchResultTitleTemplate, ws.engine.displayName, ws.query)
        case .plugin(let p):
            return p.title
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
        case .calculator:
            return LauncherStrings.calculatorResultLabel
        case .webSearch:
            return LauncherStrings.webSearchResultLabel
        case .plugin(let p):
            return p.subtitle ?? LauncherStrings.pluginResultLabel
        }
    }

    private var accessibilityLabel: String {
        switch item {
        case .application:
            return String(format: LauncherStrings.applicationResultAccessibilityLabelTemplate, title)
        case .command:
            return String(format: LauncherStrings.commandResultAccessibilityLabelTemplate, title)
        case .file:
            return String(format: LauncherStrings.fileResultAccessibilityLabelTemplate, title)
        case .calculator:
            return String(format: LauncherStrings.calculatorResultAccessibilityLabelTemplate, title)
        case .webSearch:
            return title
        case .plugin:
            return String(format: LauncherStrings.pluginResultAccessibilityLabelTemplate, title)
        }
    }

    private var accessibilityValue: String {
        switch item {
        case .application, .command, .webSearch, .plugin:
            return isSelected ? LauncherStrings.resultSelectedAccessibilityValue : ""
        case .file:
            let location = String(format: LauncherStrings.fileResultAccessibilityValueTemplate, subtitle)
            return isSelected ? [location, LauncherStrings.resultSelectedAccessibilityValue].joined(separator: ". ") : location
        case .calculator:
            return isSelected ? LauncherStrings.resultSelectedAccessibilityValue : title
        }
    }

    private var accessibilityHint: String {
        switch item {
        case .application, .file, .webSearch, .plugin:
            return LauncherStrings.openResultAccessibilityHint
        case .command:
            return LauncherStrings.runCommandAccessibilityHint
        case .calculator:
            return LauncherStrings.copyCalculatorResultAccessibilityHint
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .application(let app):
            AppIconView(
                bundleURL: app.bundleURL,
                size: CGSize(width: LauncherPanelMetrics.rowIconSize, height: LauncherPanelMetrics.rowIconSize)
            )
        case .command:
            Image(systemName: "command")
                .resizable()
                .scaledToFit()
                .padding(6)
                .foregroundStyle(LauncherGlassStyle.secondary)
                .background(iconBackground)
        case .file(let file):
            Image(
                nsImage: AppPresentationCache.shared.fileIcon(
                    for: file.path,
                    size: CGSize(width: LauncherPanelMetrics.rowIconSize, height: LauncherPanelMetrics.rowIconSize)
                )
            )
            .resizable()
            .scaledToFit()
        case .calculator:
            Image(systemName: "equal.square")
                .resizable()
                .scaledToFit()
                .padding(5)
                .foregroundStyle(LauncherGlassStyle.secondary)
                .background(iconBackground)
        case .webSearch:
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .padding(6)
                .foregroundStyle(LauncherGlassStyle.secondary)
                .background(iconBackground)
        case .plugin(let p):
            if let bundleURL = p.iconBundleURL {
                AppIconView(
                    bundleURL: bundleURL,
                    size: CGSize(width: LauncherPanelMetrics.rowIconSize, height: LauncherPanelMetrics.rowIconSize)
                )
            } else {
                Image(systemName: p.iconSystemName ?? "puzzlepiece.extension")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(LauncherGlassStyle.secondary)
                    .background(iconBackground)
            }
        }
    }

    private var subtitleColor: Color {
        isSelected ? Color.white.opacity(0.88) : LauncherGlassStyle.secondary
    }

    private var iconBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LauncherGlassStyle.capsuleFill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(LauncherGlassStyle.capsuleStroke, lineWidth: 0.8)
            )
    }
}

#Preview("Recent Section") {
    LauncherItemListView(
        sections: LauncherItemSectionBuilder.makeSections(
            items: [
                .application(AppItem(name: "TextEdit", bundleIdentifier: nil, bundleURL: URL(fileURLWithPath: "/Applications/TextEdit.app"))),
                .file(FileItem(name: "Quarterly Report.pdf", path: URL(fileURLWithPath: "/Users/demo/Documents/Quarterly Report.pdf"), contentType: nil, modificationDate: nil))
            ],
            isShowingRecentItems: true
        ),
        query: "",
        selectedIndex: 0,
        onSelect: { _ in },
        onActivate: { _ in }
    )
    .frame(width: LauncherPanelMetrics.width, height: 220)
    .padding()
    .background(.ultraThinMaterial)
}

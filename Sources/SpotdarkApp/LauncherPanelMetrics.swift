import CoreGraphics
import Foundation

enum LauncherPanelMetrics {
    static let width: CGFloat = 800
    static let searchFieldHeight: CGFloat = 52
    static let searchBarContainerHeight: CGFloat = 64
    static let collapsedHeight: CGFloat = searchBarContainerHeight
    static let expandedHeight: CGFloat = 680
    static let recentItemsLimit = 5
    static let cornerRadius: CGFloat = 18
    static let contentPadding: CGFloat = 0
    static let contentSpacing: CGFloat = 0
    static let searchFieldCornerRadius: CGFloat = 12
    static let searchBarHorizontalPadding: CGFloat = 14
    static let searchBarTopPadding: CGFloat = 6
    static let searchBarBottomPadding: CGFloat = 6
    static let resultsHorizontalPadding: CGFloat = 8
    static let resultsTopPadding: CGFloat = 8
    static let resultsBottomPadding: CGFloat = 6
    static let rowCornerRadius: CGFloat = 10
    static let rowIconSize: CGFloat = 26
    static let rowMinHeight: CGFloat = 44
    static let footerHeight: CGFloat = 42
    static let compactVerticalOffsetRatio: CGFloat = 0.12
    static let compactVerticalOffsetMaximum: CGFloat = 110
    static let expandedBottomScreenMargin: CGFloat = 16
    static let panelResizeAnimationDuration: TimeInterval = 0.22
    static let panelPresentationDuration: TimeInterval = 0.18
    static let panelDismissalDuration: TimeInterval = 0.14
    static let panelPresentationOffset: CGFloat = 14
    static let expandedContentAnimationDuration: TimeInterval = 0.22
    static let contentSwapAnimationDuration: TimeInterval = 0.18
    static let resultRowAnimationDuration: TimeInterval = 0.18
    static let selectionScrollAnimationDuration: TimeInterval = 0.14
    static let searchDebounceNanoseconds: UInt64 = 30_000_000
    static let groupedResultsMinimumCount = 5
}

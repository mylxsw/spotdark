import CoreGraphics
import Foundation

enum LauncherPanelMetrics {
    static let width: CGFloat = 720
    static let collapsedHeight: CGFloat = 84
    static let expandedHeight: CGFloat = 420
    static let cornerRadius: CGFloat = 16
    static let contentPadding: CGFloat = 16
    static let contentSpacing: CGFloat = 12
    static let searchFieldCornerRadius: CGFloat = 12
    static let searchFieldHeight: CGFloat = 52
    static let panelAnimationDuration: TimeInterval = 0.14
    static let searchDebounceNanoseconds: UInt64 = 30_000_000
}

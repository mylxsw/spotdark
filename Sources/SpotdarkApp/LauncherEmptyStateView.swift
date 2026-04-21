import SwiftUI

struct LauncherEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let hint: String?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 56, height: 56)

                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let hint {
                    Text(hint)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("No Results") {
    LauncherEmptyStateView(
        systemImage: "exclamationmark.magnifyingglass",
        title: LauncherStrings.noResultsTitle,
        message: String(format: LauncherStrings.noResultsMessageTemplate, "xcode betaaa"),
        hint: LauncherStrings.noResultsHint
    )
    .frame(width: 420, height: 220)
    .padding()
    .background(.ultraThinMaterial)
}

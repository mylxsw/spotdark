import SwiftUI

struct LauncherLoadingStateView: View {
    private let rowWidths: [CGFloat] = [0.88, 0.72, 0.81]

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 56, height: 56)

                ProgressView()
                    .controlSize(.large)
                    .tint(.accentColor)
            }

            VStack(spacing: 6) {
                Text(LauncherStrings.loadingTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(LauncherStrings.loadingMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: 320)

            VStack(spacing: 10) {
                ForEach(Array(rowWidths.enumerated()), id: \.offset) { index, width in
                    LoadingSkeletonRow(widthRatio: width)
                        .opacity(1 - (Double(index) * 0.14))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LauncherStrings.loadingTitle)
        .accessibilityValue(LauncherStrings.loadingMessage)
    }
}

private struct LoadingSkeletonRow: View {
    let widthRatio: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 32, height: 32)
                .shimmeringPlaceholder()

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 220 * widthRatio, height: 12)
                    .shimmeringPlaceholder()

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 110 * widthRatio, height: 9)
                    .shimmeringPlaceholder(delay: 0.2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ShimmeringPlaceholderModifier: ViewModifier {
    let delay: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let duration = 1.6
                        let progress = ((context.date.timeIntervalSinceReferenceDate + delay) / duration)
                            .truncatingRemainder(dividingBy: 1)
                        let width = max(geometry.size.width * 0.5, 36)
                        let xOffset = (geometry.size.width + width) * progress - width

                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.32),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: width)
                        .offset(x: xOffset)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
    }
}

private extension View {
    func shimmeringPlaceholder(delay: TimeInterval = 0) -> some View {
        modifier(ShimmeringPlaceholderModifier(delay: delay))
    }
}

#Preview("Loading") {
    LauncherLoadingStateView()
        .frame(width: 420, height: 250)
        .padding()
        .background(.ultraThinMaterial)
}

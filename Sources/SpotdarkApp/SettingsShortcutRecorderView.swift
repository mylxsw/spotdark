import AppKit
import SwiftUI
import SpotdarkCore

struct SettingsShortcutRecorderView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Button {
            store.toggleShortcutRecording()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isRecordingShortcut ? SettingsStrings.recordingShortcutTitle : SettingsStrings.currentShortcutTitle)
                            .font(.headline)
                        Text(store.isRecordingShortcut ? SettingsStrings.recordingShortcutPrompt : SettingsStrings.currentShortcutPrompt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: store.isRecordingShortcut ? "waveform.badge.mic" : "keyboard")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(store.isRecordingShortcut ? Color.accentColor : .secondary)
                }

                Text(store.isRecordingShortcut ? SettingsStrings.recordingShortcutValue : store.currentShortcutDisplay)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(store.isRecordingShortcut ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(store.isRecordingShortcut ? 0.08 : 0.05))
                    )
            }
            .padding(14)
            .background(backgroundShape)
        }
        .buttonStyle(.plain)
        .background(
            ShortcutRecorderEventMonitor(
                isActive: store.isRecordingShortcut,
                onCancel: { store.cancelShortcutRecording() },
                onShortcut: { hotKey in
                    store.applyRecordedShortcut(hotKey)
                }
            )
        )
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(store.isRecordingShortcut ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        store.isRecordingShortcut ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.14),
                        lineWidth: 1
                    )
            )
    }
}

struct SettingsShortcutFeedbackView: View {
    let feedback: SettingsStore.ShortcutFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(tintColor)

            Text(feedback.message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tintColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tintColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var symbolName: String {
        switch feedback.kind {
        case .info:
            "info.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    private var tintColor: Color {
        switch feedback.kind {
        case .info:
            .accentColor
        case .success:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

private struct ShortcutRecorderEventMonitor: NSViewRepresentable {
    let isActive: Bool
    let onCancel: () -> Void
    let onShortcut: (HotKey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onShortcut: onShortcut)
    }

    func makeNSView(context: Context) -> NSView {
        ShortcutRecorderHostView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCancel = onCancel
        context.coordinator.onShortcut = onShortcut

        if isActive {
            context.coordinator.start()
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else {
            context.coordinator.stop()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        var onCancel: () -> Void
        var onShortcut: (HotKey) -> Void

        private var monitor: Any?

        init(onCancel: @escaping () -> Void, onShortcut: @escaping (HotKey) -> Void) {
            self.onCancel = onCancel
            self.onShortcut = onShortcut
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }

                if event.keyCode == 53 {
                    onCancel()
                    return nil
                }

                guard let hotKey = HotKey(recordingEvent: event) else {
                    NSSound.beep()
                    return nil
                }

                onShortcut(hotKey)
                return nil
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private final class ShortcutRecorderHostView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private extension HotKey {
    init?(recordingEvent event: NSEvent) {
        let modifiers = HotKeyModifierFlags(eventModifiers: event.modifierFlags)
        guard !modifiers.isEmpty else { return nil }
        self.init(keyCode: event.keyCode, modifiers: modifiers)
    }
}

private extension HotKeyModifierFlags {
    init(eventModifiers: NSEvent.ModifierFlags) {
        var flags: HotKeyModifierFlags = []
        if eventModifiers.contains(.control) { flags.insert(.control) }
        if eventModifiers.contains(.option) { flags.insert(.option) }
        if eventModifiers.contains(.shift) { flags.insert(.shift) }
        if eventModifiers.contains(.command) { flags.insert(.command) }
        self = flags
    }
}

#Preview("Shortcut Recorder") {
    Form {
        SettingsShortcutRecorderView(store: .preview)
        if let feedback = SettingsStore.preview.shortcutFeedback {
            SettingsShortcutFeedbackView(feedback: feedback)
        }
    }
    .formStyle(.grouped)
    .padding(20)
    .frame(width: 520)
}

import AppKit
import SwiftUI

final class LauncherTextField: NSTextField {
    var onTextChange: ((String) -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        let liveText = (currentEditor() as? NSTextView)?.string ?? stringValue
        onTextChange?(liveText)
    }
}

final class LauncherSearchFieldContainerView: NSView {
    private static weak var activeView: LauncherSearchFieldContainerView?

    let textField: LauncherTextField
    private var shouldFocusWhenAttached = false

    override init(frame frameRect: NSRect) {
        textField = LauncherTextField()
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        textField = LauncherTextField()
        super.init(coder: coder)
        configure()
    }

    override func mouseDown(with event: NSEvent) {
        focusTextField()
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if Self.activeView === self {
                Self.activeView = nil
            }
        } else {
            Self.activeView = self
        }
        guard shouldFocusWhenAttached else { return }
        focusTextField()
    }

    @discardableResult
    static func routeUnhandledTextInput(_ text: String) -> Bool {
        guard let activeView else { return false }
        activeView.insertUnhandledText(text)
        return true
    }

    func focusTextField() {
        guard let window else {
            shouldFocusWhenAttached = true
            return
        }

        shouldFocusWhenAttached = false
        window.makeFirstResponder(textField)
        placeCursorAtEnd()
    }

    func placeCursorAtEnd() {
        guard let editor = window?.fieldEditor(false, for: textField) as? NSTextView else { return }
        editor.selectedRange = NSRange(location: textField.stringValue.utf16.count, length: 0)
    }

    private func insertUnhandledText(_ text: String) {
        guard !text.isEmpty else { return }
        focusTextField()

        if let window {
            _ = window.makeFirstResponder(textField)
        }

        if let editor = textField.currentEditor() as? NSTextView {
            editor.insertText(text, replacementRange: editor.selectedRange())
            return
        }

        textField.stringValue.append(text)
        textField.onTextChange?(textField.stringValue)
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.alignment = .left
        textField.cell?.usesSingleLineMode = true
        textField.font = .systemFont(ofSize: 18, weight: .medium)

        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
}

struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let textColor: NSColor
    let placeholderColor: NSColor
    let focusRequestID: Int
    let onMoveSelection: (Int) -> Void
    let onSubmit: () -> Void
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> LauncherSearchFieldContainerView {
        let containerView = LauncherSearchFieldContainerView()
        containerView.textField.delegate = context.coordinator
        containerView.textField.setAccessibilityLabel(LauncherStrings.searchFieldAccessibilityLabel)
        containerView.textField.setAccessibilityHelp(LauncherStrings.searchFieldAccessibilityHint)
        return containerView
    }

    func updateNSView(_ nsView: LauncherSearchFieldContainerView, context: Context) {
        context.coordinator.parent = self

        let textField = nsView.textField
        textField.onTextChange = { [weak coordinator = context.coordinator] liveText in
            coordinator?.textDidChange(liveText)
        }
        if textField.currentEditor() == nil, textField.stringValue != text {
            textField.stringValue = text
            nsView.placeCursorAtEnd()
        }

        textField.font = .systemFont(ofSize: 18, weight: .medium)
        textField.textColor = textColor
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: NSFont.systemFont(ofSize: 18, weight: .medium)
            ]
        )

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            nsView.focusTextField()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherSearchField
        var lastFocusRequestID = -1

        init(parent: LauncherSearchField) {
            self.parent = parent
        }

        func textDidChange(_ liveText: String) {
            parent.text = liveText
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            let liveText = (textField.currentEditor() as? NSTextView)?.string ?? textField.stringValue
            textDidChange(liveText)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveSelection(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveSelection(1)
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onExit()
                return true
            default:
                return false
            }
        }
    }
}

import Foundation

#if canImport(Carbon)
import Carbon
#endif

/// Represents a hotkey combination.
public struct HotKey: Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Convenience for Option(Alt) + Space.
    public static let optionSpace = HotKey(
        keyCode: 49, // kVK_Space
        modifiers: HotKeyModifier.option
    )

    /// Convenience for Command + Space.
    public static let commandSpace = HotKey(
        keyCode: 49, // kVK_Space
        modifiers: HotKeyModifier.command
    )
}

/// Carbon modifier flags for RegisterEventHotKey.
public enum HotKeyModifier {
    public static let command: UInt32 = UInt32(cmdKey)
    public static let option: UInt32 = UInt32(optionKey)
    public static let control: UInt32 = UInt32(controlKey)
    public static let shift: UInt32 = UInt32(shiftKey)
}

/// Abstraction for registering hotkeys.
public protocol HotKeyRegistering {
    func register(hotKey: HotKey, handler: @escaping () -> Void) throws
    func unregisterAll()
}

/// Errors from hotkey registration.
public enum HotKeyError: Error, Equatable {
    case carbonUnavailable
    case registrationFailed(OSStatus)
}

/// A minimal Carbon-based global hotkey manager.
///
/// Notes:
/// - This uses RegisterEventHotKey, which is the classic approach.
/// - Command+Space is likely reserved by macOS; register may fail.
public final class CarbonHotKeyManager: HotKeyRegistering {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextId: UInt32 = 1

    public init() {}

    public func register(hotKey: HotKey, handler: @escaping () -> Void) throws {
        #if canImport(Carbon)
        let id = nextId
        nextId += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x52415943), id: id) // 'RAYC'

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr else {
            throw HotKeyError.registrationFailed(status)
        }

        hotKeyRefs.append(ref)
        handlers[id] = handler
        installHandlerIfNeeded()
        #else
        throw HotKeyError.carbonUnavailable
        #endif
    }

    public func unregisterAll() {
        #if canImport(Carbon)
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        #endif
    }

    #if canImport(Carbon)
    private var isEventHandlerInstalled = false

    private func installHandlerIfNeeded() {
        guard !isEventHandlerInstalled else { return }
        isEventHandlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // We intentionally capture `self` weakly to avoid leaks.
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (nextHandler, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<CarbonHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let id = hotKeyID.id
                manager.handlers[id]?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        if status != noErr {
            // Best-effort: do not throw here because it happens after successful registration.
            // In production you should surface this error.
        }
    }
    #endif
}

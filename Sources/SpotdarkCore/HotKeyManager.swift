import Foundation

/// Platform-neutral modifier flags whose raw values match NSEvent.ModifierFlags.
public struct HotKeyModifierFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt

    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let shift   = HotKeyModifierFlags(rawValue: 1 << 17)  // 131072
    public static let control = HotKeyModifierFlags(rawValue: 1 << 18)  // 262144
    public static let option  = HotKeyModifierFlags(rawValue: 1 << 19)  // 524288
    public static let command = HotKeyModifierFlags(rawValue: 1 << 20)  // 1048576
}

/// A hotkey combination defined by a virtual key code and modifier flags.
public struct HotKey: Equatable, Hashable, Sendable {
    /// Virtual key code (same codes used by Carbon kVK_* and NSEvent.keyCode).
    public let keyCode: UInt16
    public let modifiers: HotKeyModifierFlags

    public init(keyCode: UInt16, modifiers: HotKeyModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Option(Alt) + Space.
    public static let optionSpace  = HotKey(keyCode: 49, modifiers: .option)

    /// Command + Space (likely reserved by Spotlight).
    public static let commandSpace = HotKey(keyCode: 49, modifiers: .command)

    /// Human-readable display string, e.g. "⌘Space".
    public var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeDisplayString)
        return parts.joined()
    }

    private var keyCodeDisplayString: String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 36: return "Return"
        case 51: return "Delete"
        case 53: return "Esc"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default: return "Key(\(keyCode))"
        }
    }
}

/// Errors from hotkey registration or monitoring.
public enum HotKeyError: Error, Equatable {
    /// Accessibility permissions are required for global event monitoring.
    case accessibilityPermissionRequired
    /// The system rejected the monitor registration (rare; monitor returned nil).
    case monitorRegistrationFailed
}

/// Abstraction for registering global hotkeys.
///
/// `register` may throw synchronously (e.g. permission denied at call time).
/// Post-registration errors (e.g. permission revoked) arrive via `onError`.
public protocol HotKeyRegistering: AnyObject {
    /// Called on the main thread when an async error occurs after registration.
    var onError: ((HotKeyError) -> Void)? { get set }

    /// Register a global hotkey. Throws `HotKeyError` if immediate setup fails.
    func register(hotKey: HotKey, handler: @escaping @Sendable () -> Void) throws

    /// Remove all registered hotkeys and monitors.
    func unregisterAll()
}

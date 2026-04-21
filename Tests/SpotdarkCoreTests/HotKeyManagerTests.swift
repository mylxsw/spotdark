import XCTest
@testable import SpotdarkCore

final class HotKeyManagerTests: XCTestCase {
    func testDisplayStringFormatsCommandOptionLetterShortcut() {
        let hotKey = HotKey(keyCode: 17, modifiers: [.command, .option])

        XCTAssertEqual(hotKey.displayString, "⌥⌘T")
    }

    func testDisplayStringFormatsNavigationShortcut() {
        let hotKey = HotKey(keyCode: 123, modifiers: [.control, .shift])

        XCTAssertEqual(hotKey.displayString, "⌃⇧Left Arrow")
    }
}

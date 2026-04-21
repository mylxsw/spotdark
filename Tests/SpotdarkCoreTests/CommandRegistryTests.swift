import XCTest
@testable import SpotdarkCore

final class CommandRegistryTests: XCTestCase {
    func testRegisterReplacesSameId() {
        let registry = CommandRegistry()
        registry.register(CommandItem(id: "a", title: "A", keywords: []))
        registry.register(CommandItem(id: "a", title: "A2", keywords: ["x"]))

        let commands = registry.allCommands()
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.title, "A2")
    }
}

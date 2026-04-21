import XCTest
@testable import SpotdarkCore

final class CommandRegistryTests: XCTestCase {
    func testEmptyRegistryReturnsNoCommands() {
        let registry = CommandRegistry()
        XCTAssertTrue(registry.allCommands().isEmpty)
    }

    func testInitWithCommandsExposesThemImmediately() {
        let items = [
            CommandItem(id: "a", title: "Alpha", keywords: []),
            CommandItem(id: "b", title: "Beta", keywords: [])
        ]
        let registry = CommandRegistry(commands: items)
        XCTAssertEqual(registry.allCommands(), items)
    }

    func testRegisterAddsNewCommand() {
        let registry = CommandRegistry()
        registry.register(CommandItem(id: "a", title: "A", keywords: []))
        XCTAssertEqual(registry.allCommands().count, 1)
    }

    func testRegisterReplacesSameId() {
        let registry = CommandRegistry()
        registry.register(CommandItem(id: "a", title: "A", keywords: []))
        registry.register(CommandItem(id: "a", title: "A2", keywords: ["x"]))

        let commands = registry.allCommands()
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.title, "A2")
    }

    func testRegisterMultipleDifferentIds() {
        let registry = CommandRegistry()
        registry.register(CommandItem(id: "a", title: "A", keywords: []))
        registry.register(CommandItem(id: "b", title: "B", keywords: []))
        registry.register(CommandItem(id: "c", title: "C", keywords: []))
        XCTAssertEqual(registry.allCommands().count, 3)
    }
}

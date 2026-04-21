import XCTest
@testable import SpotdarkCore

final class LauncherViewModelTests: XCTestCase {
    func testUpdateQueryUpdatesResults() {
        let apps = [AppItem(name: "Xcode", bundleIdentifier: nil, bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"))]
        let engine = SearchEngine(apps: apps, commands: [])
        let vm = LauncherViewModel(engineProvider: { engine })

        vm.updateQuery("x")
        XCTAssertEqual(vm.results, [.application(apps[0])])

        vm.updateQuery("zzz")
        XCTAssertEqual(vm.results, [])
    }
}

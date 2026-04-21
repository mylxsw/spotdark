import XCTest
@testable import SpotdarkCore

final class CachedAppProviderTests: XCTestCase {
    func testFirstCallFetchesFromBase() throws {
        let base = SpyAppProvider(apps: [
            AppItem(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                    bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"))
        ])
        let cached = CachedAppProvider(base: base)

        let result = try cached.fetchApplications()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(base.fetchCount, 1)
    }

    func testSubsequentCallsReturnCachedResultWithoutCallingBase() throws {
        let base = SpyAppProvider(apps: [
            AppItem(name: "Xcode", bundleIdentifier: nil,
                    bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"))
        ])
        let cached = CachedAppProvider(base: base)

        _ = try cached.fetchApplications()
        _ = try cached.fetchApplications()
        _ = try cached.fetchApplications()

        XCTAssertEqual(base.fetchCount, 1)
    }

    func testInvalidateForcesRefetchOnNextCall() throws {
        let base = SpyAppProvider(apps: [
            AppItem(name: "TextEdit", bundleIdentifier: nil,
                    bundleURL: URL(fileURLWithPath: "/Applications/TextEdit.app"))
        ])
        let cached = CachedAppProvider(base: base)

        _ = try cached.fetchApplications()
        cached.invalidate()
        _ = try cached.fetchApplications()

        XCTAssertEqual(base.fetchCount, 2)
    }

    func testInvalidateWithoutPriorFetchDoesNotCrash() throws {
        let base = SpyAppProvider(apps: [])
        let cached = CachedAppProvider(base: base)

        cached.invalidate()
        let result = try cached.fetchApplications()

        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(base.fetchCount, 1)
    }
}

private final class SpyAppProvider: AppProviding {
    private(set) var fetchCount = 0
    private let apps: [AppItem]

    init(apps: [AppItem]) {
        self.apps = apps
    }

    func fetchApplications() throws -> [AppItem] {
        fetchCount += 1
        return apps
    }
}

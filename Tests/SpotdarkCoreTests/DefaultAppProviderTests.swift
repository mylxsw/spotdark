import XCTest
@testable import SpotdarkCore

final class DefaultAppProviderTests: XCTestCase {
    func testFetchApplicationsFindsAppsRecursively() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: base) }

        let root = base.appendingPathComponent("Applications", isDirectory: true)
        let utilities = root.appendingPathComponent("Utilities", isDirectory: true)
        try fm.createDirectory(at: utilities, withIntermediateDirectories: true)

        let rootApp = root.appendingPathComponent("RootApp.app", isDirectory: true)
        let nestedApp = utilities.appendingPathComponent("NestedApp.app", isDirectory: true)
        try createFakeAppBundle(at: rootApp, bundleName: "RootApp")
        try createFakeAppBundle(at: nestedApp, bundleName: "NestedApp")

        let provider = DefaultAppProvider(fileManager: fm, appDirectories: [root], maxDepth: 2)
        let apps = try provider.fetchApplications()

        XCTAssertEqual(Set(apps.map { $0.name }), Set(["RootApp", "NestedApp"]))
    }

    func testFetchApplicationsRespectsMaxDepth() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: base) }

        let root = base.appendingPathComponent("Applications", isDirectory: true)
        let level1 = root.appendingPathComponent("L1", isDirectory: true)
        let level2 = level1.appendingPathComponent("L2", isDirectory: true)
        try fm.createDirectory(at: level2, withIntermediateDirectories: true)

        let tooDeepApp = level2.appendingPathComponent("TooDeep.app", isDirectory: true)
        try createFakeAppBundle(at: tooDeepApp, bundleName: "TooDeep")

        let provider = DefaultAppProvider(fileManager: fm, appDirectories: [root], maxDepth: 1)
        let apps = try provider.fetchApplications()

        XCTAssertTrue(apps.isEmpty)
    }

    private func createFakeAppBundle(at url: URL, bundleName: String) throws {
        let fm = FileManager.default
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)

        let plistURL = contents.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleName": bundleName,
            "CFBundleIdentifier": "test.\(bundleName.lowercased())"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }
}

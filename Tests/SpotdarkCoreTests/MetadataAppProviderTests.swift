import XCTest
@testable import SpotdarkCore

final class MetadataAppProviderTests: XCTestCase {
    func testMetadataAppProviderBuildsItemsFromURLs() throws {
        let fake = FakeMetadataQuery(urls: [
            URL(fileURLWithPath: "/Applications/Safari.app"),
            URL(fileURLWithPath: "/System/Applications/Mail.app"),
            URL(fileURLWithPath: "/Applications/NotAnApp.txt")
        ])

        let provider = MetadataAppProvider(query: fake)
        let apps = try provider.fetchApplications()

        XCTAssertEqual(Set(apps.map { $0.name }), Set(["Safari", "Mail"]))
    }

    private struct FakeMetadataQuery: MetadataQuerying {
        let urls: [URL]
        func fetchApplicationBundleURLs() throws -> [URL] { urls }
    }
}

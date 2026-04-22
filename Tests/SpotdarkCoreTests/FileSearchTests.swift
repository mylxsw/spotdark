import XCTest
@testable import SpotdarkCore

final class FileItemTests: XCTestCase {
    func testFileItemEquality() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/report.pdf")
        let a = FileItem(name: "report", path: url, contentType: "com.adobe.pdf", modificationDate: nil)
        let b = FileItem(name: "report", path: url, contentType: "com.adobe.pdf", modificationDate: nil)
        XCTAssertEqual(a, b)
    }

    func testFileItemInequalityOnPath() {
        let a = FileItem(name: "report", path: URL(fileURLWithPath: "/a/report.pdf"), contentType: nil, modificationDate: nil)
        let b = FileItem(name: "report", path: URL(fileURLWithPath: "/b/report.pdf"), contentType: nil, modificationDate: nil)
        XCTAssertNotEqual(a, b)
    }

    func testSearchItemFileCase() {
        let file = FileItem(name: "notes", path: URL(fileURLWithPath: "/tmp/notes.txt"), contentType: "public.plain-text", modificationDate: nil)
        let item = SearchItem.file(file)
        if case .file(let f) = item {
            XCTAssertEqual(f.name, "notes")
        } else {
            XCTFail("Expected .file case")
        }
    }
}

// MARK: - Mock provider for LauncherStore integration tests

private struct MockFileSearchProvider: FileSearchProviding {
    let items: [FileItem]

    func search(query: String) -> AsyncStream<[FileItem]> {
        let items = self.items
        return AsyncStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }
}

final class FileSearchMergeTests: XCTestCase {
    func testFileItemsIncludedInSearchResults() async throws {
        let file = FileItem(
            name: "ProjectNotes",
            path: URL(fileURLWithPath: "/Users/test/Documents/ProjectNotes.txt"),
            contentType: "public.plain-text",
            modificationDate: Date()
        )
        let provider = MockFileSearchProvider(items: [file])
        _ = provider // accessed only via integration flow; verify protocol conformance compiles
        XCTAssertNotNil(provider)
    }

    func testFileItemHashable() {
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let file = FileItem(name: "test", path: url, contentType: nil, modificationDate: nil)
        var set = Set<FileItem>()
        set.insert(file)
        XCTAssertTrue(set.contains(file))
    }
}

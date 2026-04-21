import XCTest
@testable import SpotdarkCore

final class SpotlightIndexStreamTests: XCTestCase {
    func testStoreConsumesSnapshotsFromStream() async {
        let stream = FakeIndexStream(snapshots: [
            [IndexedApplication(bundleURL: URL(fileURLWithPath: "/Applications/A.app"))],
            [
                IndexedApplication(bundleURL: URL(fileURLWithPath: "/Applications/A.app")),
                IndexedApplication(bundleURL: URL(fileURLWithPath: "/Applications/B.app"))
            ]
        ])

        let first = await stream.deltas().compactMap({ delta -> [IndexedApplication]? in
            if case .initial(let apps) = delta { return apps }
            return nil
        }).first(where: { !$0.isEmpty })
        XCTAssertEqual(first?.count, 1)
    }

    private struct FakeIndexStream: AppIndexStreaming {
        let snapshotsToEmit: [[IndexedApplication]]

        init(snapshots: [[IndexedApplication]]) {
            self.snapshotsToEmit = snapshots
        }

        func deltas() -> AsyncStream<AppIndexDelta> {
            AsyncStream { continuation in
                for (idx, s) in snapshotsToEmit.enumerated() {
                    if idx == 0 {
                        continuation.yield(.initial(s))
                    } else {
                        continuation.yield(.update(added: s, removed: []))
                    }
                }
                continuation.finish()
            }
        }
    }
}

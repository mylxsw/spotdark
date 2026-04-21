import XCTest
@testable import SpotdarkCore

final class SearchEngineTests: XCTestCase {
    func testUsageBoostAffectsRankingWhenMatchScoreEqual() {
        let appA = AppItem(name: "Alpha", bundleIdentifier: nil, bundleURL: URL(fileURLWithPath: "/Applications/Alpha.app"))
        let appB = AppItem(name: "Alpine", bundleIdentifier: nil, bundleURL: URL(fileURLWithPath: "/Applications/Alpine.app"))

        struct Usage: UsageScoring {
            func score(forAppBundleURL url: URL) -> Int { url.lastPathComponent == "Alpine.app" ? 100 : 0 }
            func score(forCommandID id: String) -> Int { 0 }
        }

        let engine = SearchEngine(apps: [appA, appB], commands: [], usage: Usage())
        // Both are prefix matches for "al" (same match score), so usage should decide.
        let results = engine.search(query: "al")
        XCTAssertEqual(results.first, .application(appB))
    }

    func testSearchReturnsEmptyForBlankQuery() {
        let engine = SearchEngine(apps: [], commands: [])
        XCTAssertEqual(engine.search(query: ""), [])
        XCTAssertEqual(engine.search(query: "   "), [])
    }

    func testAppPrefixMatchRanksHigherThanSubstring() {
        let apps = [
            AppItem(name: "Safari", bundleIdentifier: "com.apple.Safari", bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")),
            AppItem(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
        ]
        let engine = SearchEngine(apps: apps, commands: [])
        let results = engine.search(query: "sa")
        XCTAssertEqual(results.first, .application(apps[0]))
    }

    func testCommandKeywordMatchWorks() {
        let commands = [
            CommandItem(id: "open-settings", title: "Open Settings", keywords: ["preferences", "settings"])
        ]
        let engine = SearchEngine(apps: [], commands: commands)
        let results = engine.search(query: "pref")
        XCTAssertEqual(results, [.command(commands[0])])
    }
}

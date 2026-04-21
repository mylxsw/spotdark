import Foundation

/// Provides ranking boosts based on usage.
public protocol UsageScoring {
    /// Higher value means more important.
    func score(forAppBundleURL url: URL) -> Int
    func score(forCommandID id: String) -> Int
}

public struct NoUsageScoring: UsageScoring {
    public init() {}
    public func score(forAppBundleURL url: URL) -> Int { 0 }
    public func score(forCommandID id: String) -> Int { 0 }
}

/// Search engine that matches apps and commands.
public final class SearchEngine {
    private let apps: [AppItem]
    private let commands: [CommandItem]
    private let usage: UsageScoring

    public init(apps: [AppItem], commands: [CommandItem], usage: UsageScoring = NoUsageScoring()) {
        self.apps = apps
        self.commands = commands
        self.usage = usage
    }

    /// Performs a search and returns ranked items.
    public func search(query: String, limit: Int = 20) -> [SearchItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()

        var scored: [(SearchItem, Int)] = []

        for app in apps {
            if let score = scoreMatch(text: app.name, query: lower) {
                // Lower is better. Usage is a boost (subtract from score).
                let boost = usage.score(forAppBundleURL: app.bundleURL)
                let finalScore = score * 1000 - boost
                scored.append((.application(app), finalScore))
            }
        }

        for cmd in commands {
            // Match against title + keywords.
            var bestScore: Int? = scoreMatch(text: cmd.title, query: lower)
            for kw in cmd.keywords {
                if let s = scoreMatch(text: kw, query: lower) {
                    bestScore = min(bestScore ?? s, s)
                }
            }
            if let bestScore {
                let boost = usage.score(forCommandID: cmd.id)
                let finalScore = bestScore * 1000 - boost
                scored.append((.command(cmd), finalScore))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            // Stable tie-breaker by visible title.
            return title(of: lhs.0) < title(of: rhs.0)
        }

        return scored.prefix(limit).map { $0.0 }
    }

    private func title(of item: SearchItem) -> String {
        switch item {
        case .application(let app):
            return app.name
        case .command(let cmd):
            return cmd.title
        }
    }

    /// Lower score = better match.
    ///
    /// Scoring rules (starter):
    /// - 0: prefix match
    /// - 1: word boundary match
    /// - 2: substring match
    private func scoreMatch(text: String, query: String) -> Int? {
        let t = text.lowercased()
        if t.hasPrefix(query) { return 0 }
        if t.contains(" " + query) { return 1 }
        if t.contains(query) { return 2 }
        return nil
    }
}

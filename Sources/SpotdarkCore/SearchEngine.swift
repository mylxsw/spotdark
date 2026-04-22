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
        case .file(let file):
            return file.name
        }
    }

    /// Lower score = better match.
    ///
    /// Scoring rules:
    /// - 0: prefix match
    /// - 1: word boundary match
    /// - 2: substring match
    /// - 3: fuzzy match (Levenshtein distance ≤ threshold against any space-delimited word)
    private func scoreMatch(text: String, query: String) -> Int? {
        let t = text.lowercased()
        if t.hasPrefix(query) { return 0 }
        if t.contains(" " + query) { return 1 }
        if t.contains(query) { return 2 }
        // Fuzzy: require at least 3 chars to avoid noise.
        let maxDist = query.count >= 5 ? 2 : query.count >= 3 ? 1 : 0
        if maxDist > 0 {
            for word in t.split(separator: " ").map(String.init) {
                if levenshtein(word, query) <= maxDist { return 3 }
            }
        }
        return nil
    }

    /// Standard Levenshtein edit distance (O(m·n) time, O(n) space).
    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        // Early-exit: if lengths differ by more than the allowed max, skip.
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                curr[j] = a[i-1] == b[j-1]
                    ? prev[j-1]
                    : 1 + Swift.min(prev[j], curr[j-1], prev[j-1])
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}

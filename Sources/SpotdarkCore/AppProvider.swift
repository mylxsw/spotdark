import Foundation

/// Provides installed applications.
public protocol AppProviding {
    func fetchApplications() async throws -> [AppItem]
}

/// Default app provider: scans common application folders.
///
/// Notes:
/// - This implementation is intentionally simple for a starter project.
/// - For production use, consider using LaunchServices APIs and caching.
public final class DefaultAppProvider: AppProviding {
    private let fileManager: FileManager
    private let appDirectories: [URL]
    private let maxDepth: Int

    /// - Parameters:
    ///   - appDirectories: Root directories to scan.
    ///   - maxDepth: Maximum recursion depth. `0` means only the root directory itself.
    public init(
        fileManager: FileManager = .default,
        appDirectories: [URL]? = nil,
        maxDepth: Int = 2
    ) {
        self.fileManager = fileManager
        self.maxDepth = max(0, maxDepth)

        if let appDirectories {
            self.appDirectories = appDirectories
        } else {
            self.appDirectories = DefaultAppProvider.defaultApplicationDirectories(fileManager: fileManager)
        }
    }

    public func fetchApplications() throws -> [AppItem] {
        var collected: [AppItem] = []
        var seenURLs = Set<URL>()

        for dir in appDirectories {
            guard fileManager.fileExists(atPath: dir.path) else { continue }
            collectApps(in: dir, depth: 0, collected: &collected, seenURLs: &seenURLs)
        }

        // Sort for stable UI.
        return collected.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func collectApps(
        in directory: URL,
        depth: Int,
        collected: inout [AppItem],
        seenURLs: inout Set<URL>
    ) {
        guard depth <= maxDepth else { return }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents {
            if url.pathExtension.lowercased() == "app" {
                guard !seenURLs.contains(url) else { continue }
                seenURLs.insert(url)

                if let item = readAppItem(fromBundleURL: url) {
                    collected.append(item)
                }
                continue
            }

            // Recurse into subdirectories (useful for /Applications/Utilities etc.).
            guard depth < maxDepth else { continue }
            guard let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory), isDir == true else {
                continue
            }
            // Avoid traversing into app bundles.
            if url.pathExtension.lowercased() == "app" { continue }

            collectApps(in: url, depth: depth + 1, collected: &collected, seenURLs: &seenURLs)
        }
    }

    private func readAppItem(fromBundleURL url: URL) -> AppItem? {
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL) else {
            // Fallback to folder name.
            return AppItem(name: url.deletingPathExtension().lastPathComponent, bundleIdentifier: nil, bundleURL: url)
        }
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return AppItem(name: url.deletingPathExtension().lastPathComponent, bundleIdentifier: nil, bundleURL: url)
        }

        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleId = plist["CFBundleIdentifier"] as? String
        return AppItem(name: name, bundleIdentifier: bundleId, bundleURL: url)
    }

    public static func defaultApplicationDirectories(fileManager: FileManager = .default) -> [URL] {
        var dirs: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true)
        ]

        let home = fileManager.homeDirectoryForCurrentUser
        dirs.append(home.appendingPathComponent("Applications", isDirectory: true))

        // Common non-App Store location.
        dirs.append(URL(fileURLWithPath: "/usr/local/Caskroom", isDirectory: true))

        return dirs
    }
}

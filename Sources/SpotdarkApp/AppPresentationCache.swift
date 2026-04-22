import AppKit
import Foundation

/// Caches application icons and display names to keep scrolling smooth.
@MainActor
final class AppPresentationCache {
    static let shared = AppPresentationCache()

    private let iconCache = NSCache<NSURL, NSImage>()
    private let nameCache = NSCache<NSURL, NSString>()
    private var inFlightIconLoads: [NSURL: Task<Data?, Never>] = [:]

    private init() {
        iconCache.countLimit = 512
        nameCache.countLimit = 2048
    }

    func displayName(for bundleURL: URL) -> String {
        if let cached = nameCache.object(forKey: bundleURL as NSURL) {
            return cached as String
        }

        let name = Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent

        nameCache.setObject(name as NSString, forKey: bundleURL as NSURL)
        return name
    }

    func cachedIcon(for bundleURL: URL, size: CGSize) -> NSImage? {
        guard let cached = iconCache.object(forKey: bundleURL as NSURL) else {
            return nil
        }

        return preparedIcon(from: cached, size: size)
    }

    func loadIcon(for bundleURL: URL, size: CGSize) async -> NSImage {
        let cacheKey = bundleURL as NSURL

        if let cached = iconCache.object(forKey: cacheKey) {
            return preparedIcon(from: cached, size: size)
        }

        let loadTask: Task<Data?, Never>
        if let existingTask = inFlightIconLoads[cacheKey] {
            loadTask = existingTask
        } else {
            let task = Task.detached(priority: .utility) {
                Self.loadIconData(for: bundleURL)
            }

            inFlightIconLoads[cacheKey] = task
            loadTask = task
        }

        let iconData = await loadTask.value
        inFlightIconLoads[cacheKey] = nil
        let image = if let iconData, let loadedImage = NSImage(data: iconData) {
            loadedImage
        } else {
            NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        iconCache.setObject(image, forKey: cacheKey)
        return preparedIcon(from: image, size: size)
    }

    func fileIcon(for path: URL, size: CGSize) -> NSImage {
        let cacheKey = path as NSURL
        if let cached = iconCache.object(forKey: cacheKey) {
            return preparedIcon(from: cached, size: size)
        }
        let image = NSWorkspace.shared.icon(forFile: path.path)
        iconCache.setObject(image, forKey: cacheKey)
        return preparedIcon(from: image, size: size)
    }

    func invalidate(bundleURL: URL) {
        iconCache.removeObject(forKey: bundleURL as NSURL)
        nameCache.removeObject(forKey: bundleURL as NSURL)
        inFlightIconLoads[bundleURL as NSURL]?.cancel()
        inFlightIconLoads[bundleURL as NSURL] = nil
    }

    private func preparedIcon(from image: NSImage, size: CGSize) -> NSImage {
        let sizedImage = (image.copy() as? NSImage) ?? image
        sizedImage.size = size
        return sizedImage
    }

    nonisolated private static func loadIconData(for bundleURL: URL) -> Data? {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard
            let plistData = try? Data(contentsOf: infoPlistURL, options: [.mappedIfSafe]),
            let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }

        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let iconNames = iconNames(from: plist)

        for iconName in iconNames {
            for candidateURL in iconCandidateURLs(named: iconName, resourcesURL: resourcesURL) {
                if let iconData = try? Data(contentsOf: candidateURL, options: [.mappedIfSafe]) {
                    return iconData
                }
            }
        }

        return nil
    }

    nonisolated private static func iconNames(from plist: [String: Any]) -> [String] {
        var names: [String] = []

        if let iconFile = plist["CFBundleIconFile"] as? String {
            names.append(iconFile)
        }

        if let iconName = plist["CFBundleIconName"] as? String {
            names.append(iconName)
        }

        if let primaryIcon = (plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: iconFiles)
        }

        return Array(NSOrderedSet(array: names.filter { !$0.isEmpty })) as? [String] ?? []
    }

    nonisolated private static func iconCandidateURLs(named iconName: String, resourcesURL: URL) -> [URL] {
        let basename = iconName.hasSuffix(".icns") ? String(iconName.dropLast(5)) : iconName
        return [
            resourcesURL.appendingPathComponent(iconName),
            resourcesURL.appendingPathComponent("\(iconName).icns"),
            resourcesURL.appendingPathComponent("\(basename).icns")
        ]
    }
}

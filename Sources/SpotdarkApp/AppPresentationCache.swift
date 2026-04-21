import AppKit
import Foundation

/// Caches application icons and display names to keep scrolling smooth.
@MainActor
final class AppPresentationCache {
    static let shared = AppPresentationCache()

    private let iconCache = NSCache<NSURL, NSImage>()
    private let nameCache = NSCache<NSURL, NSString>()

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

    func icon(for bundleURL: URL, size: CGSize) -> NSImage {
        if let cached = iconCache.object(forKey: bundleURL as NSURL) {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        image.size = size
        iconCache.setObject(image, forKey: bundleURL as NSURL)
        return image
    }

    func invalidate(bundleURL: URL) {
        iconCache.removeObject(forKey: bundleURL as NSURL)
        nameCache.removeObject(forKey: bundleURL as NSURL)
    }
}

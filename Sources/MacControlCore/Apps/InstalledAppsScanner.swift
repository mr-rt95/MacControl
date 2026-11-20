//
//  InstalledAppsScanner.swift
//  MacControlCore
//

import Foundation
import CoreServices

/// Lists installed applications with size and last-used date.
public final class InstalledAppsScanner {

    private let searchRoots: [URL]
    private let protection: ProtectedPaths

    public init(searchRoots: [URL] = [URL(fileURLWithPath: "/Applications"),
                                      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")],
                protection: ProtectedPaths = ProtectedPaths()) {
        self.searchRoots = searchRoots
        self.protection = protection
    }

    /// Scans `/Applications` and `~/Applications` (one folder level deep). Run off the main thread.
    public func scan(isCancelled: () -> Bool = { false }) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for root in searchRoots {
            for url in applicationBundles(in: root) {
                if isCancelled() { return apps }
                apps.append(describe(url))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private

    private func applicationBundles(in root: URL) -> [URL] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                             options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                result.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let inner = try? manager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles]) {
                result += inner.filter { $0.pathExtension == "app" }
            }
        }
        return result
    }

    private func describe(_ url: URL) -> InstalledApp {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let identifier = bundle?.bundleIdentifier
        return InstalledApp(
            url: url, name: name, bundleIdentifier: identifier,
            version: info["CFBundleShortVersionString"] as? String,
            bytes: DirectorySize.bytes(of: url),
            lastUsed: Self.lastUsedDate(of: url),
            protection: protection.protection(forApplication: url, bundleIdentifier: identifier)
        )
    }

    /// Spotlight's `kMDItemLastUsedDate`.
    static func lastUsedDate(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

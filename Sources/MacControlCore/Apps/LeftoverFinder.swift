//
//  LeftoverFinder.swift
//  MacControlCore
//

import Foundation

/// Finds preferences, caches, containers, logs and launch agents that belong to an application.
///
/// Matching is deliberately conservative: it needs the bundle identifier (or, for a few folders,
/// the exact application name), never a loose substring, so unrelated files are not offered.
public final class LeftoverFinder {

    /// How an entry of a library folder is matched.
    private enum Match {
        case bundleID            // name == id or starts with "id."
        case containsBundleID    // Group Containers: "TEAMID.com.vendor.app"
        case bundleIDOrName      // folder named like the app is also accepted
    }

    private static let userFolders: [(String, Match)] = [
        ("Application Support", .bundleIDOrName), ("Caches", .bundleIDOrName), ("Logs", .bundleIDOrName),
        ("Preferences", .bundleID), ("Containers", .bundleID), ("Group Containers", .containsBundleID),
        ("Saved Application State", .bundleID), ("LaunchAgents", .bundleID), ("HTTPStorages", .bundleID),
        ("WebKit", .bundleID), ("Cookies", .bundleID), ("Application Scripts", .bundleID)
    ]

    private static let systemFolders: [(String, Match)] = [
        ("Application Support", .bundleIDOrName), ("Caches", .bundleID), ("Preferences", .bundleID),
        ("LaunchAgents", .bundleID), ("LaunchDaemons", .bundleID), ("PrivilegedHelperTools", .bundleID)
    ]

    private let userLibrary: URL
    private let systemLibrary: URL

    public init(userLibrary: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"),
                systemLibrary: URL = URL(fileURLWithPath: "/Library")) {
        self.userLibrary = userLibrary
        self.systemLibrary = systemLibrary
    }

    /// Returns leftovers sorted by size. Apple applications return nothing.
    public func find(bundleIdentifier: String?, appName: String) -> [Leftover] {
        guard !(bundleIdentifier ?? "").hasPrefix("com.apple.") else { return [] }
        let identifier = Self.usable(identifier: bundleIdentifier)
        var found: [Leftover] = []

        for (library, folders, isSystem) in [(userLibrary, Self.userFolders, false), (systemLibrary, Self.systemFolders, true)] {
            for (folder, match) in folders {
                let directory = library.appendingPathComponent(folder)
                guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
                for entry in entries where Self.matches(entry, identifier: identifier, appName: appName, rule: match) {
                    let url = directory.appendingPathComponent(entry)
                    let deletable = !isSystem || FileManager.default.isDeletableFile(atPath: url.path)
                    found.append(Leftover(url: url, bytes: DirectorySize.bytes(of: url), requiresAdministrator: !deletable))
                }
            }
        }
        return found.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Matching (pure, unit-tested)

    /// A bundle identifier is only trusted when it looks like a reverse-DNS name.
    static func usable(identifier: String?) -> String? {
        guard let identifier = identifier, identifier.count >= 5, identifier.contains(".") else { return nil }
        return identifier
    }

    private static func matches(_ entry: String, identifier: String?, appName: String, rule: Match) -> Bool {
        if let id = identifier {
            switch rule {
            case .bundleID, .bundleIDOrName:
                if entry == id || entry.hasPrefix(id + ".") { return true }
            case .containsBundleID:
                if entry == id || entry.hasSuffix("." + id) || entry.hasPrefix(id + ".") { return true }
            }
        }
        if rule == .bundleIDOrName, appName.count >= 4, entry.lowercased() == appName.lowercased() { return true }
        return false
    }

    static func matchesForTesting(_ entry: String, identifier: String?, appName: String, inGroupContainers: Bool) -> Bool {
        matches(entry, identifier: usable(identifier: identifier), appName: appName,
                rule: inGroupContainers ? .containsBundleID : .bundleIDOrName)
    }
}

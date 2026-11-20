//
//  ProtectedPaths.swift
//  MacControlCore
//

import Foundation

/// Why a path may not be removed.
public enum ProtectionReason: Equatable {
    /// Operating system location (`/System`, `/usr`, `/bin`, `/sbin`, `/private`, system `/Library`, …).
    case systemPath
    /// The home folder, `~/Library` or a top-level user folder itself (only their contents may be touched).
    case structuralFolder
    /// Documents, Desktop or Pictures: never selected automatically, only on explicit user choice.
    case personalFolder
    /// An Apple application that ships with macOS.
    case appleApplication
}

/// Central rule set that decides what the app may never delete.
///
/// The list is compiled into the app and cannot be switched off by the user. Every deletion
/// path in the project goes through `check(_:allowPersonal:)` before touching a file.
public struct ProtectedPaths {

    private let home: String
    private let userTemp: String
    private let systemRoots: [String]
    private let structuralFolders: Set<String>
    private let personalRoots: [String]

    /// - Parameter home: home folder; injectable so tests never depend on the real one.
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let homePath = Self.normalize(home)
        self.home = homePath
        self.userTemp = Self.normalize(URL(fileURLWithPath: NSTemporaryDirectory()))
        self.systemRoots = ["/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/etc", "/var",
                            "/dev", "/cores", "/opt", "/Volumes", "/Network"]
        self.structuralFolders = [
            "/", "/Applications", "/Users", homePath,
            homePath + "/Library", homePath + "/Applications", homePath + "/Downloads",
            homePath + "/Documents", homePath + "/Desktop", homePath + "/Pictures",
            homePath + "/Movies", homePath + "/Music", homePath + "/Public"
        ]
        self.personalRoots = [homePath + "/Documents", homePath + "/Desktop", homePath + "/Pictures"]
    }

    /// Returns `nil` when the item may be moved to the Trash, otherwise the reason it may not.
    ///
    /// - Parameter allowPersonal: `true` only when the user picked this exact item by hand
    ///   (large files, duplicates). Automatic cleanup always passes `false`.
    public func check(_ url: URL, allowPersonal: Bool = false) -> ProtectionReason? {
        let path = Self.normalize(url)

        // The per-user temporary folder lives under /private/var but is exactly what "temporary files" cleans.
        let inUserTemp = path.hasPrefix(userTemp + "/")
        if !inUserTemp {
            if systemRoots.contains(where: { Self.isEqualOrInside(path, $0) }) { return .systemPath }
        }
        if structuralFolders.contains(path) || path == userTemp { return .structuralFolder }
        if !allowPersonal, personalRoots.contains(where: { Self.isEqualOrInside(path, $0) }) {
            return .personalFolder
        }
        return nil
    }

    /// `true` if the path is inside Documents, Desktop or Pictures.
    public func isPersonal(_ url: URL) -> Bool {
        let path = Self.normalize(url)
        return personalRoots.contains { Self.isEqualOrInside(path, $0) }
    }

    /// Checks whether an application bundle belongs to Apple's built-in set.
    /// Apple apps from the Mac App Store (Pages, Xcode, …) carry a receipt and may be removed.
    public func protection(forApplication url: URL, bundleIdentifier: String?) -> ProtectionReason? {
        let path = Self.normalize(url)
        if path.hasPrefix("/System/") || path.hasPrefix("/Applications/Utilities/") { return .appleApplication }
        if (bundleIdentifier ?? "").hasPrefix("com.apple.") {
            let receipt = url.appendingPathComponent("Contents/_MASReceipt/receipt")
            if !FileManager.default.fileExists(atPath: receipt.path) { return .appleApplication }
        }
        return nil
    }

    // MARK: - Helpers

    /// Resolves symlinks and `..` so a path cannot dodge the rules through indirection.
    static func normalize(_ url: URL) -> String {
        var path = url.resolvingSymlinksInPath().standardizedFileURL.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func isEqualOrInside(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}

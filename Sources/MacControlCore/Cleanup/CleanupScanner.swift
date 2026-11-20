//
//  CleanupScanner.swift
//  MacControlCore
//

import Foundation

/// Finds removable files in a fixed whitelist of known-safe locations. Nothing outside the
/// whitelist is ever listed, and nothing is selected for the user.
public final class CleanupScanner {

    /// Folders older than this are offered under "old downloads".
    public static let oldDownloadsAge: TimeInterval = 90 * 86_400
    /// Temporary files younger than this may still be in use and are left alone.
    public static let temporaryFileMinimumAge: TimeInterval = 3 * 86_400

    private let home: URL
    private let temporaryDirectory: URL
    private let now: () -> Date

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory()),
                now: @escaping () -> Date = Date.init) {
        self.home = home
        self.temporaryDirectory = temporaryDirectory
        self.now = now
    }

    /// Scans one category. Run it off the main thread: it walks the file system.
    public func scan(_ category: CleanupCategory, isCancelled: () -> Bool = { false }) -> CleanupCategoryResult {
        switch category {
        case .userCaches:
            return children(of: "Library/Caches", category: .userCaches, risk: .safe,
                            exclude: { $0.hasPrefix("com.apple.") }, isCancelled: isCancelled)
        case .logs:
            return children(of: "Library/Logs", category: .logs, risk: .safe,
                            exclude: { $0.hasPrefix("com.apple.") }, isCancelled: isCancelled)
        case .trash:
            return children(of: ".Trash", category: .trash, risk: .personal, exclude: { _ in false }, isCancelled: isCancelled)
        case .oldDownloads:
            let cutoff = now().addingTimeInterval(-Self.oldDownloadsAge)
            return children(of: "Downloads", category: .oldDownloads, risk: .personal,
                            exclude: { _ in false }, olderThan: cutoff, isCancelled: isCancelled)
        case .temporaryFiles:
            let cutoff = now().addingTimeInterval(-Self.temporaryFileMinimumAge)
            return list(directory: temporaryDirectory, category: .temporaryFiles, risk: .safe,
                        exclude: { $0.hasPrefix(".") }, olderThan: cutoff, isCancelled: isCancelled)
        case .developerCaches:
            return developerCaches(isCancelled: isCancelled)
        case .iosBackups:
            return children(of: "Library/Application Support/MobileSync/Backup", category: .iosBackups,
                            risk: .irreplaceable, exclude: { _ in false }, isCancelled: isCancelled)
        }
    }

    // MARK: - Developer caches

    private func developerCaches(isCancelled: () -> Bool) -> CleanupCategoryResult {
        var items: [CleanupItem] = []
        var denied = false

        let derived = list(directory: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                           category: .developerCaches, risk: .safe, exclude: { _ in false }, isCancelled: isCancelled)
        items += derived.items
        denied = denied || derived.accessDenied

        let support = list(directory: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
                           category: .developerCaches, risk: .safe, exclude: { _ in false }, isCancelled: isCancelled)
        items += support.items

        // Single-folder caches: listed as one item each.
        for relative in [".npm/_cacache", ".gradle/caches"] {
            let url = home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path), !isCancelled() else { continue }
            items.append(CleanupItem(url: url, name: relative, bytes: DirectorySize.bytes(of: url, isCancelled: isCancelled),
                                     modified: modificationDate(url), category: .developerCaches, risk: .safe))
        }
        return CleanupCategoryResult(category: .developerCaches,
                                     items: items.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes },
                                     accessDenied: denied)
    }

    // MARK: - Generic listing

    private func children(of relativePath: String, category: CleanupCategory, risk: CleanupRisk,
                          exclude: (String) -> Bool, olderThan cutoff: Date? = nil,
                          isCancelled: () -> Bool) -> CleanupCategoryResult {
        list(directory: home.appendingPathComponent(relativePath), category: category, risk: risk,
             exclude: exclude, olderThan: cutoff, isCancelled: isCancelled)
    }

    private func list(directory: URL, category: CleanupCategory, risk: CleanupRisk,
                      exclude: (String) -> Bool, olderThan cutoff: Date? = nil,
                      isCancelled: () -> Bool) -> CleanupCategoryResult {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else {
            return CleanupCategoryResult(category: category, items: [], accessDenied: false)
        }

        let contents: [URL]
        do {
            contents = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                       options: [])
        } catch {
            // EPERM/EACCES on a TCC-protected folder such as ~/.Trash.
            let code = (error as NSError).code
            let denied = code == NSFileReadNoPermissionError || (error as NSError).domain == NSPOSIXErrorDomain
            return CleanupCategoryResult(category: category, items: [], accessDenied: denied)
        }

        var items: [CleanupItem] = []
        for url in contents {
            if isCancelled() { break }
            let name = url.lastPathComponent
            if exclude(name) { continue }
            let modified = modificationDate(url)
            if let cutoff = cutoff, let modified = modified, modified > cutoff { continue }
            let bytes = DirectorySize.bytes(of: url, isCancelled: isCancelled)
            guard bytes > 0 else { continue }
            items.append(CleanupItem(url: url, name: name, bytes: bytes, modified: modified, category: category, risk: risk))
        }
        return CleanupCategoryResult(category: category, items: items.sorted { $0.bytes > $1.bytes }, accessDenied: false)
    }

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

/// Lists local Time Machine snapshots (read-only; removing them needs administrator rights).
public enum TimeMachineSnapshots {

    public static func list() -> [TimeMachineSnapshot] {
        guard let result = CommandRunner.execute("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 20),
              result.succeeded else { return [] }
        return parse(result.output)
    }

    /// Parses `com.apple.TimeMachine.2026-11-20-123456.local` lines.
    static func parse(_ output: String) -> [TimeMachineSnapshot] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return output.split(separator: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("com.apple.TimeMachine.") else { return nil }
            let stamp = text.dropFirst("com.apple.TimeMachine.".count).prefix { $0 != "." }
            return TimeMachineSnapshot(name: text, date: formatter.date(from: String(stamp)))
        }
    }
}

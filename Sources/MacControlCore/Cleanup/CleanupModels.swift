//
//  CleanupModels.swift
//  MacControlCore
//

import Foundation

/// Groups of removable files shown on the Cleanup screen.
public enum CleanupCategory: String, CaseIterable, Identifiable {
    case userCaches
    case logs
    case trash
    case oldDownloads
    case temporaryFiles
    case developerCaches
    case iosBackups

    public var id: String { rawValue }
}

/// How carefully an item must be confirmed.
public enum CleanupRisk: Int, Comparable {
    /// Regenerated automatically (caches, logs, temp files).
    case safe = 0
    /// Belongs to the user (old downloads): chosen manually, never preselected.
    case personal = 1
    /// May be the only copy of the data (iPhone backups): needs explicit acknowledgement.
    case irreplaceable = 2

    public static func < (lhs: CleanupRisk, rhs: CleanupRisk) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct CleanupItem: Identifiable, Hashable {
    public let url: URL
    public let name: String
    public let bytes: UInt64
    public let modified: Date?
    public let category: CleanupCategory
    public let risk: CleanupRisk

    public var id: URL { url }

    public init(url: URL, name: String, bytes: UInt64, modified: Date?, category: CleanupCategory, risk: CleanupRisk) {
        self.url = url
        self.name = name
        self.bytes = bytes
        self.modified = modified
        self.category = category
        self.risk = risk
    }
}

/// Result of scanning one category.
public struct CleanupCategoryResult: Equatable {
    public let category: CleanupCategory
    public let items: [CleanupItem]
    /// `true` when macOS refused access (needs "Full Disk Access").
    public let accessDenied: Bool

    public var totalBytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }

    public init(category: CleanupCategory, items: [CleanupItem], accessDenied: Bool) {
        self.category = category
        self.items = items
        self.accessDenied = accessDenied
    }
}

/// A local Time Machine snapshot. Deleting it needs administrator rights (unsupported without the helper).
public struct TimeMachineSnapshot: Identifiable, Equatable {
    public let name: String
    public let date: Date?
    public var id: String { name }
}

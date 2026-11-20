//
//  ActionLog.swift
//  MacControlCore
//

import Foundation

public enum ActionKind: String, Codable {
    case cleanup, uninstall, duplicates, largeFiles
}

/// One file moved to the Trash by the app.
public struct ActionItem: Codable, Equatable {
    public let originalPath: String
    /// Where it sits in the Trash now (`nil` if macOS did not report it).
    public let trashPath: String?
    public let bytes: UInt64
    public var isRestored: Bool
    /// Set when the item was moved by the privileged helper into its quarantine (restored through the helper).
    public let quarantineID: String?

    public init(originalPath: String, trashPath: String?, bytes: UInt64, isRestored: Bool = false, quarantineID: String? = nil) {
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.bytes = bytes
        self.isRestored = isRestored
        self.quarantineID = quarantineID
    }
}

/// A user-confirmed operation and what it moved.
public struct ActionRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let kind: ActionKind
    /// Free-form description, shown in the activity list.
    public let title: String
    public var items: [ActionItem]

    public var totalBytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }
    public var canUndo: Bool { items.contains { !$0.isRestored && ($0.trashPath != nil || $0.quarantineID != nil) } }

    public init(id: UUID = UUID(), date: Date = Date(), kind: ActionKind, title: String, items: [ActionItem]) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.items = items
    }
}

/// Persistent journal of the app's own actions, so every one of them can be undone from the Trash.
public final class ActionLog {

    private static let maximumRecords = 200

    private let lock = NSLock()
    private let fileURL: URL?
    private var storedRecords: [ActionRecord] = []

    /// `~/Library/Application Support/MacControl/actions.json`
    public static var defaultFileURL: URL? {
        AppSupport.directory?.appendingPathComponent("actions.json")
    }

    public init(fileURL: URL? = ActionLog.defaultFileURL) {
        self.fileURL = fileURL
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            storedRecords = (try? decoder.decode([ActionRecord].self, from: data)) ?? []
        }
    }

    /// Newest first.
    public var records: [ActionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return storedRecords.sorted { $0.date > $1.date }
    }

    public func append(_ record: ActionRecord) {
        lock.lock()
        storedRecords.append(record)
        if storedRecords.count > Self.maximumRecords {
            storedRecords.removeFirst(storedRecords.count - Self.maximumRecords)
        }
        lock.unlock()
        save()
    }

    public func record(id: UUID) -> ActionRecord? {
        lock.lock()
        defer { lock.unlock() }
        return storedRecords.first { $0.id == id }
    }

    /// Marks items of a record as restored.
    public func markRestored(recordID: UUID, originalPaths: Set<String>) {
        lock.lock()
        if let index = storedRecords.firstIndex(where: { $0.id == recordID }) {
            for itemIndex in storedRecords[index].items.indices
            where originalPaths.contains(storedRecords[index].items[itemIndex].originalPath) {
                storedRecords[index].items[itemIndex].isRestored = true
            }
        }
        lock.unlock()
        save()
    }

    private func save() {
        guard let url = fileURL else { return }
        lock.lock()
        let snapshot = storedRecords
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

//
//  SafeTrasher.swift
//  MacControlCore
//

import Foundation

/// Moves a file to the Trash. Abstracted so tests never touch the real Trash.
public protocol FileTrashing {
    /// Returns the item's new location in the Trash, if known.
    func trash(_ url: URL) throws -> URL?
    func restore(from trashed: URL, to original: URL) throws
}

/// Uses `FileManager.trashItem`, which remembers the original location so Finder's "Put Back" works.
public struct SystemFileTrasher: FileTrashing {

    public init() {}

    public func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    public func restore(from trashed: URL, to original: URL) throws {
        try FileManager.default.moveItem(at: trashed, to: original)
    }
}

/// An item the user confirmed for removal.
public struct TrashRequest: Equatable {
    public let url: URL
    public let bytes: UInt64
    /// `true` only for items the user picked by hand inside a personal folder.
    public let allowPersonal: Bool

    public init(url: URL, bytes: UInt64, allowPersonal: Bool = false) {
        self.url = url
        self.bytes = bytes
        self.allowPersonal = allowPersonal
    }
}

public struct TrashFailure: Equatable {
    public enum Reason: Equatable {
        case protected(ProtectionReason)
        case missing
        case failed(String)
    }
    public let url: URL
    public let reason: Reason
}

public struct TrashReport {
    public let recordID: UUID?
    public let trashed: [ActionItem]
    public let failures: [TrashFailure]

    public var trashedBytes: UInt64 { trashed.reduce(0) { $0 + $1.bytes } }
}

public struct RestoreReport {
    public let restored: Int
    public let failed: Int
}

/// The only gate through which the app removes files: checks protection, moves to the Trash and
/// records the operation so it can be undone. Nothing is ever deleted permanently here.
public final class SafeTrasher {

    private let protection: ProtectedPaths
    private let trasher: FileTrashing
    public let log: ActionLog

    public init(protection: ProtectedPaths = ProtectedPaths(), trasher: FileTrashing = SystemFileTrasher(),
                log: ActionLog = ActionLog()) {
        self.protection = protection
        self.trasher = trasher
        self.log = log
    }

    /// Moves every allowed request to the Trash and logs the result.
    /// A failure on one item never stops the others.
    public func execute(_ requests: [TrashRequest], kind: ActionKind, title: String) -> TrashReport {
        var done: [ActionItem] = []
        var failures: [TrashFailure] = []

        for request in requests {
            if let reason = protection.check(request.url, allowPersonal: request.allowPersonal) {
                failures.append(TrashFailure(url: request.url, reason: .protected(reason)))
                continue
            }
            guard FileManager.default.fileExists(atPath: request.url.path) ||
                  (try? request.url.checkResourceIsReachable()) == true else {
                failures.append(TrashFailure(url: request.url, reason: .missing))
                continue
            }
            do {
                let trashed = try trasher.trash(request.url)
                done.append(ActionItem(originalPath: request.url.path, trashPath: trashed?.path, bytes: request.bytes))
            } catch {
                failures.append(TrashFailure(url: request.url, reason: .failed(error.localizedDescription)))
            }
        }

        var recordID: UUID?
        if !done.isEmpty {
            let record = ActionRecord(kind: kind, title: title, items: done)
            log.append(record)
            recordID = record.id
        }
        return TrashReport(recordID: recordID, trashed: done, failures: failures)
    }

    /// Puts the items of a record back where they were. Items whose original spot is taken, or that
    /// were already removed from the Trash, are skipped and counted as failed.
    public func undo(recordID: UUID) -> RestoreReport {
        guard let record = log.record(id: recordID) else { return RestoreReport(restored: 0, failed: 0) }
        var restored = Set<String>()
        var failed = 0

        for item in record.items where !item.isRestored && item.quarantineID == nil {   // helper items are restored by the app
            guard let trashPath = item.trashPath,
                  FileManager.default.fileExists(atPath: trashPath),
                  !FileManager.default.fileExists(atPath: item.originalPath) else { failed += 1; continue }
            do {
                try trasher.restore(from: URL(fileURLWithPath: trashPath), to: URL(fileURLWithPath: item.originalPath))
                restored.insert(item.originalPath)
            } catch {
                failed += 1
            }
        }
        log.markRestored(recordID: recordID, originalPaths: restored)
        return RestoreReport(restored: restored.count, failed: failed)
    }
}

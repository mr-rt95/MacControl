//
//  DuplicateFinder.swift
//  MacControlCore
//

import Foundation
import CryptoKit

/// Identical files. `files` always has at least two entries with the same content.
public struct DuplicateGroup: Identifiable, Equatable {
    public let id: String          // content hash
    public let bytes: UInt64       // size of one copy
    public let files: [URL]

    public init(id: String, bytes: UInt64, files: [URL]) {
        self.id = id
        self.bytes = bytes
        self.files = files
    }

    /// Space freed by keeping a single copy.
    public var wastedBytes: UInt64 { bytes * UInt64(max(files.count - 1, 0)) }
}

/// Finds duplicate files in three passes: by size, by partial checksum, then by full SHA-256.
/// Each pass only looks at candidates that survived the previous one, so most files are never fully read.
public final class DuplicateFinder {

    private static let partialLength = 64 * 1024
    private static let chunkLength = 1024 * 1024

    private let roots: [URL]
    private let minimumBytes: UInt64

    public init(roots: [URL], minimumBytes: UInt64 = 1_048_576) {
        self.roots = roots
        self.minimumBytes = minimumBytes
    }

    public func find(isCancelled: () -> Bool = { false }) -> [DuplicateGroup] {
        // Pass 1: group by size.
        var bySize: [UInt64: [URL]] = [:]
        var seenIdentifiers = Set<AnyHashable>()   // skips hard links to the same data
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .fileResourceIdentifierKey]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                if isCancelled() { return [] }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, UInt64(size) >= minimumBytes else { continue }
                if let identifier = values.fileResourceIdentifier as? AnyHashable, !seenIdentifiers.insert(identifier).inserted { continue }
                bySize[UInt64(size), default: []].append(url)
            }
        }

        // Pass 2 and 3: partial then full checksum.
        var groups: [DuplicateGroup] = []
        for (size, urls) in bySize where urls.count > 1 {
            if isCancelled() { return [] }
            let byPartial = Dictionary(grouping: urls) { Self.hash(of: $0, partial: true) ?? UUID().uuidString }
            for candidates in byPartial.values where candidates.count > 1 {
                let byFull = Dictionary(grouping: candidates) { Self.hash(of: $0, partial: false, isCancelled: isCancelled) ?? UUID().uuidString }
                for (hash, files) in byFull where files.count > 1 {
                    groups.append(DuplicateGroup(id: hash, bytes: size, files: files.sorted { $0.path < $1.path }))
                }
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    // MARK: - Hashing

    /// SHA-256 of the whole file, or of its first and last 64 KB when `partial` is set.
    static func hash(of url: URL, partial: Bool, isCancelled: () -> Bool = { false }) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()

        if partial {
            guard let head = try? handle.read(upToCount: partialLength) else { return nil }
            hasher.update(data: head)
            if let end = try? handle.seekToEnd(), end > UInt64(partialLength) * 2 {
                try? handle.seek(toOffset: end - UInt64(partialLength))
                if let tail = try? handle.read(upToCount: partialLength) { hasher.update(data: tail) }
            }
        } else {
            while !isCancelled() {
                guard let chunk = try? handle.read(upToCount: chunkLength), !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

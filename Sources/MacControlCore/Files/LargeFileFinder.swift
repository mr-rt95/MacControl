//
//  LargeFileFinder.swift
//  MacControlCore
//

import Foundation

public struct FoundFile: Identifiable, Equatable {
    public let url: URL
    public let bytes: UInt64
    public let lastAccessed: Date?
    public let modified: Date?
    public var id: URL { url }
}

/// Finds the biggest files and the ones not opened for a long time.
///
/// Personal folders are scanned too, but results there are never selected automatically.
public final class LargeFileFinder {

    private let roots: [URL]
    private let skippedDirectories: Set<String>

    /// - Parameter roots: folders to search (home by default). `~/Library` and the Trash are skipped.
    public init(roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser], skippedDirectories: [URL] = []) {
        self.roots = roots
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = [home.appendingPathComponent("Library"), home.appendingPathComponent(".Trash")]
        self.skippedDirectories = Set((defaults + skippedDirectories).map { ProtectedPaths.normalize($0) })
    }

    /// - Parameters:
    ///   - minimumBytes: files smaller than this are ignored.
    ///   - notOpenedSince: when set, only files last opened before this date are returned.
    ///   - limit: maximum number of results, biggest first.
    public func find(minimumBytes: UInt64, notOpenedSince: Date? = nil, limit: Int = 200,
                     isCancelled: () -> Bool = { false }) -> [FoundFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
                                      .contentAccessDateKey, .contentModificationDateKey]
        var results: [FoundFile] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }

            for case let url as URL in enumerator {
                if isCancelled() { return Self.top(results, limit) }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

                if values.isDirectory == true {
                    if skippedDirectories.contains(ProtectedPaths.normalize(url)) { enumerator.skipDescendants() }
                    continue
                }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let bytes = UInt64(values.totalFileAllocatedSize ?? 0)
                guard bytes >= minimumBytes else { continue }

                let accessed = values.contentAccessDate
                if let threshold = notOpenedSince {
                    guard let accessed = accessed, accessed < threshold else { continue }
                }
                results.append(FoundFile(url: url, bytes: bytes, lastAccessed: accessed, modified: values.contentModificationDate))
            }
        }
        return Self.top(results, limit)
    }

    private static func top(_ files: [FoundFile], _ limit: Int) -> [FoundFile] {
        Array(files.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}

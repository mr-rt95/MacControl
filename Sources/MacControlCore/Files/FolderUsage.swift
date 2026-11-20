//
//  FolderUsage.swift
//  MacControlCore
//

import Foundation

/// One entry of a folder listing with its total size.
public struct FolderEntry: Identifiable, Equatable {
    public let url: URL
    public let bytes: UInt64
    public let isDirectory: Bool
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
}

/// Answers "what takes the most space here?": the direct children of a folder, biggest first.
/// Read-only; used with drill-down so the user can follow the space down to the culprit.
public final class FolderUsage {

    public init() {}

    /// The direct children of `folder` (hidden ones included, symbolic links not followed).
    public static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                      options: [])) ?? []
    }

    /// Measures every child and reports each result as soon as it is known, so the UI can fill in progressively.
    /// - Parameters:
    ///   - onEntry: called on the calling thread after each child is measured.
    ///   - isCancelled: polled between and during measurements.
    public func measure(folder: URL, isCancelled: () -> Bool = { false }, onEntry: (FolderEntry) -> Void) {
        for url in Self.children(of: folder) {
            if isCancelled() { return }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            let bytes = DirectorySize.bytes(of: url, isCancelled: isCancelled)
            if isCancelled() { return }
            onEntry(FolderEntry(url: url, bytes: bytes, isDirectory: values?.isDirectory == true))
        }
    }
}

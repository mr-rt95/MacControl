//
//  DirectorySize.swift
//  MacControlCore
//

import Foundation

/// Disk usage of files and folders.
public enum DirectorySize {

    /// Allocated size in bytes of a file, or of everything inside a folder. Symbolic links are not followed.
    /// - Parameter isCancelled: polled during the walk so long scans can be abandoned.
    public static func bytes(of url: URL, isCancelled: () -> Bool = { false }) -> UInt64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let manager = FileManager.default

        if let values = try? url.resourceValues(forKeys: Set(keys)) {
            if values.isSymbolicLink == true { return 0 }
            if values.isRegularFile == true {
                return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }

        guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }

        var total: UInt64 = 0
        for case let file as URL in enumerator {
            if isCancelled() { return total }
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

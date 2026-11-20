//
//  DiskMonitor.swift
//  MacControlCore
//

import Foundation
import IOKit

/// Reports startup-volume capacity (via `URLResourceValues`) and disk throughput (via IOKit).
public final class DiskMonitor {

    private struct Counters {
        let bytesRead: UInt64
        let bytesWritten: UInt64
        let time: UInt64   // nanoseconds, monotonic
    }

    private var previous: Counters?
    private let volumeURL: URL

    public init(volumeURL: URL = URL(fileURLWithPath: "/")) {
        self.volumeURL = volumeURL
    }

    /// Returns capacity and throughput since the previous call.
    /// Throughput is zero on the first call.
    public func sample() -> DiskStats {
        let (total, available) = readCapacity()
        var readRate = 0.0, writeRate = 0.0

        if let current = readCounters() {
            if let previous = previous, current.time > previous.time {
                let seconds = Double(current.time - previous.time) / 1_000_000_000
                // Counters only grow; guard against a device disappearing between samples.
                readRate = Double(current.bytesRead >= previous.bytesRead ? current.bytesRead - previous.bytesRead : 0) / seconds
                writeRate = Double(current.bytesWritten >= previous.bytesWritten ? current.bytesWritten - previous.bytesWritten : 0) / seconds
            }
            previous = current
        }

        return DiskStats(totalBytes: total, availableBytes: available,
                         readBytesPerSecond: readRate, writeBytesPerSecond: writeRate)
    }

    // MARK: - Private

    private func readCapacity() -> (total: UInt64, available: UInt64) {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? volumeURL.resourceValues(forKeys: keys) else { return (0, 0) }
        let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
        // "Important usage" includes purgeable space the system can reclaim on demand.
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return (total, UInt64(max(0, available)))
    }

    /// Sums the cumulative byte counters of every `IOBlockStorageDriver`.
    private func readCounters() -> Counters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
        var foundDriver = false

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            foundDriver = true
            bytesRead += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            bytesWritten += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }

        guard foundDriver else { return nil }
        return Counters(bytesRead: bytesRead, bytesWritten: bytesWritten, time: MachTime.nowNanoseconds)
    }
}

//
//  NetworkMonitor.swift
//  MacControlCore
//

import Foundation

/// Measures aggregate network throughput from interface byte counters (`getifaddrs`).
///
/// Only physical Ethernet/Wi-Fi interfaces (`en*`) are counted, so traffic that passes
/// through VPN tunnels or bridges is not counted twice.
public final class NetworkMonitor {

    private struct Counters {
        var bytesIn: UInt32
        var bytesOut: UInt32
    }

    private var previous: [String: Counters]?
    private var previousTime: UInt64 = 0

    public init() {}

    /// Returns throughput since the previous call. The first call returns `.zero`.
    public func sample() -> NetworkStats {
        let current = readCounters()
        let now = MachTime.nowNanoseconds
        defer {
            previous = current
            previousTime = now
        }

        guard let previous = previous, now > previousTime else { return .zero }
        let seconds = Double(now - previousTime) / 1_000_000_000

        var bytesIn: UInt64 = 0, bytesOut: UInt64 = 0
        for (name, new) in current {
            guard let old = previous[name] else { continue }
            // ifi_ibytes / ifi_obytes are 32-bit and wrap around at 4 GiB.
            bytesIn += UInt64(new.bytesIn &- old.bytesIn)
            bytesOut += UInt64(new.bytesOut &- old.bytesOut)
        }
        return NetworkStats(downloadBytesPerSecond: Double(bytesIn) / seconds,
                            uploadBytesPerSecond: Double(bytesOut) / seconds)
    }

    // MARK: - Private

    private func readCounters() -> [String: Counters] {
        var result: [String: Counters] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }

            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data else { continue }

            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }

            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = Counters(bytesIn: stats.ifi_ibytes, bytesOut: stats.ifi_obytes)
        }
        return result
    }
}

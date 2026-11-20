//
//  ProcessMonitor.swift
//  MacControlCore
//

import Foundation
import Darwin
import CLibProc

/// Enumerates processes through libproc (no `ps`/`top` invocation) and computes
/// CPU and disk rates from consecutive `proc_pid_rusage` readings.
///
/// Without administrator rights libproc only reveals processes of the current user;
/// other processes are silently skipped.
public final class ProcessMonitor {

    /// Cumulative counters for one process, used to derive rates.
    private struct Counters {
        let cpuNanoseconds: UInt64
        let diskRead: UInt64
        let diskWritten: UInt64
        let startTime: UInt64
        let time: UInt64
    }

    /// Data that never changes during the life of a process.
    private struct StaticInfo {
        let name: String
        let groupKey: String
        let groupName: String
        let uid: UInt32
        let path: String?
        let startTime: UInt64
    }

    private var previousCounters: [Int32: Counters] = [:]
    private var staticCache: [Int32: StaticInfo] = [:]

    public init() {}

    /// Returns one sample per visible process. Rates are zero for processes seen for the first time.
    public func sample() -> [ProcessSample] {
        let now = MachTime.nowNanoseconds
        var counters: [Int32: Counters] = [:]
        var samples: [ProcessSample] = []

        for pid in Self.allPIDs() where pid >= 0 {   // pid 0 is kernel_task (readable only with root)
            guard let usage = Self.resourceUsage(pid: pid) else { continue }
            let startTime = usage.ri_proc_start_abstime
            let info = staticInfo(pid: pid, startTime: startTime)

            let current = Counters(
                cpuNanoseconds: MachTime.nanoseconds(fromTicks: usage.ri_user_time &+ usage.ri_system_time),
                diskRead: usage.ri_diskio_bytesread,
                diskWritten: usage.ri_diskio_byteswritten,
                startTime: startTime,
                time: now
            )
            counters[pid] = current

            var cpuPercent = 0.0, readRate = 0.0, writeRate = 0.0
            if let old = previousCounters[pid], old.startTime == startTime, now > old.time {
                let elapsed = Double(now - old.time)
                cpuPercent = Double(current.cpuNanoseconds &- old.cpuNanoseconds) / elapsed * 100
                let seconds = elapsed / 1_000_000_000
                readRate = Double(current.diskRead &- old.diskRead) / seconds
                writeRate = Double(current.diskWritten &- old.diskWritten) / seconds
            }

            samples.append(ProcessSample(
                pid: pid, name: info.name, groupKey: info.groupKey, groupName: info.groupName,
                uid: info.uid, cpuPercent: max(0, cpuPercent), memoryBytes: usage.ri_phys_footprint,
                diskReadBytesPerSecond: readRate, diskWriteBytesPerSecond: writeRate, path: info.path
            ))
        }

        previousCounters = counters
        // Drop cache entries of processes that have exited.
        staticCache = staticCache.filter { counters[$0.key] != nil }
        return samples
    }

    // MARK: - Grouping helpers (pure, unit-tested)

    /// Extracts the outermost `.app` bundle from an executable path.
    ///
    /// `/Applications/Google Chrome.app/Contents/.../Google Chrome Helper.app/Contents/MacOS/Helper`
    /// → `("/Applications/Google Chrome.app", "Google Chrome")`.
    static func appBundle(fromExecutablePath path: String) -> (path: String, name: String)? {
        let bundlePath: String
        if let range = path.range(of: ".app/") {
            bundlePath = String(path[..<range.lowerBound]) + ".app"
        } else if path.hasSuffix(".app") {
            bundlePath = path
        } else {
            return nil
        }
        let name = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
        return name.isEmpty ? nil : (bundlePath, name)
    }

    // MARK: - Private

    private func staticInfo(pid: Int32, startTime: UInt64) -> StaticInfo {
        if let cached = staticCache[pid], cached.startTime == startTime { return cached }

        let path = Self.executablePath(pid: pid)
        let name = Self.processName(pid: pid) ?? path.map { ($0 as NSString).lastPathComponent } ?? "pid \(pid)"
        let group = path.flatMap(Self.appBundle(fromExecutablePath:))

        let info = StaticInfo(
            name: name,
            groupKey: group?.path ?? name,
            groupName: group?.name ?? name,
            uid: Self.owner(pid: pid),
            path: path,
            startTime: startTime
        )
        staticCache[pid] = info
        return info
    }

    private static func allPIDs() -> [Int32] {
        // proc_listallpids returns the number of PIDs (not bytes, unlike proc_listpids).
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        // Leave headroom: processes may be spawned between the two calls.
        var pids = [Int32](repeating: 0, count: Int(estimated) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        guard count > 0 else { return [] }
        return Array(pids.prefix(min(Int(count), pids.count)))
    }

    private static func resourceUsage(pid: Int32) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? usage : nil
    }

    static func processName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    static func owner(pid: Int32) -> UInt32 {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return UInt32.max }
        return info.pbi_uid
    }
}

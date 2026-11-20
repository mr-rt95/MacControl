//
//  ProcessSample.swift
//  MacControlCore
//

import Foundation

/// Resource usage of a single process.
public struct ProcessSample: Equatable, Identifiable, Codable {

    public let pid: Int32
    /// Process name as reported by the kernel.
    public let name: String
    /// Key used to merge helper processes with their parent app (bundle path or process name).
    public let groupKey: String
    /// Human-readable name of the owning app (e.g. "Google Chrome" for "Google Chrome Helper").
    public let groupName: String
    public let uid: UInt32
    /// CPU usage in percent of one core (may exceed 100 on multi-core machines).
    public let cpuPercent: Double
    /// Physical memory footprint in bytes.
    public let memoryBytes: UInt64
    public let diskReadBytesPerSecond: Double
    public let diskWriteBytesPerSecond: Double
    /// Executable path, when it could be read.
    public let path: String?

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, groupKey: String, groupName: String, uid: UInt32,
                cpuPercent: Double, memoryBytes: UInt64,
                diskReadBytesPerSecond: Double, diskWriteBytesPerSecond: Double, path: String? = nil) {
        self.path = path
        self.pid = pid
        self.name = name
        self.groupKey = groupKey
        self.groupName = groupName
        self.uid = uid
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
    }
}

/// All processes that belong to one application, merged into a single row.
public struct ProcessGroup: Equatable, Identifiable {

    public let id: String
    public let name: String
    public let pids: [Int32]
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let diskReadBytesPerSecond: Double
    public let diskWriteBytesPerSecond: Double
    /// Facts about the group's main process, so the UI can judge protection without system calls
    /// (also for processes of other users, which this user cannot inspect).
    public let executablePath: String?
    public let ownerUID: UInt32?
    /// Name of the main process (as opposed to the application's display name).
    public let processName: String?

    public var processCount: Int { pids.count }
    public var diskBytesPerSecond: Double { diskReadBytesPerSecond + diskWriteBytesPerSecond }

    public init(id: String, name: String, pids: [Int32], cpuPercent: Double, memoryBytes: UInt64,
                diskReadBytesPerSecond: Double, diskWriteBytesPerSecond: Double,
                executablePath: String? = nil, ownerUID: UInt32? = nil, processName: String? = nil) {
        self.executablePath = executablePath
        self.ownerUID = ownerUID
        self.processName = processName
        self.id = id
        self.name = name
        self.pids = pids
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
    }

    /// Merges per-process samples into per-application groups.
    public static func group(_ samples: [ProcessSample]) -> [ProcessGroup] {
        var buckets: [String: [ProcessSample]] = [:]
        for sample in samples {
            buckets[sample.groupKey, default: []].append(sample)
        }
        return buckets.map { key, members in
            // The group takes the display name of its first (lowest pid) member,
            // which is normally the main app process rather than a helper.
            let leader = members.min { $0.pid < $1.pid }
            return ProcessGroup(
                id: key,
                name: leader?.groupName ?? key,
                pids: members.map(\.pid).sorted(),
                cpuPercent: members.reduce(0) { $0 + $1.cpuPercent },
                memoryBytes: members.reduce(0) { $0 + $1.memoryBytes },
                diskReadBytesPerSecond: members.reduce(0) { $0 + $1.diskReadBytesPerSecond },
                diskWriteBytesPerSecond: members.reduce(0) { $0 + $1.diskWriteBytesPerSecond },
                executablePath: leader?.path,
                ownerUID: leader?.uid,
                processName: leader?.name
            )
        }
    }
}

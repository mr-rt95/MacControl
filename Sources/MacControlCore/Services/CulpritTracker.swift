//
//  CulpritTracker.swift
//  MacControlCore
//

import Foundation

/// Finds the application most responsible for load, from accumulated CPU time and memory growth
/// over the last minutes (not from a single noisy sample).
public final class CulpritTracker {

    private struct Entry {
        var name: String
        var cpuScore = 0.0          // exponentially decayed CPU-seconds
        var cpuPercent = 0.0
        var memoryBytes: UInt64 = 0
        var busySeconds: TimeInterval = 0
    }

    /// Time constant of the CPU score decay.
    private let cpuWindow: TimeInterval
    /// CPU share above which an app counts as "busy".
    private let busyThreshold: Double
    /// Minimum score (≈ 5 % average CPU over the window) to name an app at all.
    private let minimumScore: Double

    private var entries: [String: Entry] = [:]

    public init(cpuWindow: TimeInterval = 120, busyThreshold: Double = 20, minimumScore: Double? = nil) {
        self.cpuWindow = cpuWindow
        self.busyThreshold = busyThreshold
        self.minimumScore = minimumScore ?? 0.05 * cpuWindow
    }

    /// Feeds one process snapshot covering `elapsed` seconds.
    public func update(groups: [ProcessGroup], elapsed: TimeInterval) {
        guard elapsed > 0 else { return }
        let decay = exp(-elapsed / cpuWindow)
        var next: [String: Entry] = [:]

        for group in groups {
            var entry = entries[group.id] ?? Entry(name: group.name)
            entry.name = group.name
            entry.cpuScore = entry.cpuScore * decay + group.cpuPercent / 100 * elapsed
            entry.cpuPercent = group.cpuPercent
            entry.memoryBytes = group.memoryBytes
            entry.busySeconds = group.cpuPercent >= busyThreshold ? entry.busySeconds + elapsed : 0
            next[group.id] = entry
        }
        entries = next   // applications that exited are forgotten
    }

    /// Application with the largest recent CPU consumption, if any is significant.
    public var cpuCulprit: Culprit? {
        guard let top = entries.values.max(by: { $0.cpuScore < $1.cpuScore }),
              top.cpuScore >= minimumScore else { return nil }
        return Culprit(name: top.name, cpuPercent: top.cpuPercent,
                       memoryBytes: top.memoryBytes, activeSeconds: top.busySeconds)
    }

    /// Application holding the most memory.
    public var memoryCulprit: Culprit? {
        guard let top = entries.values.max(by: { $0.memoryBytes < $1.memoryBytes }),
              top.memoryBytes > 0 else { return nil }
        return Culprit(name: top.name, cpuPercent: top.cpuPercent,
                       memoryBytes: top.memoryBytes, activeSeconds: top.busySeconds)
    }
}

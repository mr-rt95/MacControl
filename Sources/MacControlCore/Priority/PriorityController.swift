//
//  PriorityController.swift
//  MacControlCore
//

import Foundation

/// The three operating modes.
public enum PerformanceMode: String, CaseIterable, Identifiable {
    /// Nothing changed.
    case normal
    /// Background apps run at low priority to reduce heat and fan noise.
    case quiet
    /// Priorities are back to normal and heavy background apps are suggested for closing.
    case performance

    public var id: String { rawValue }
}

/// Lowers and restores the scheduling priority of the user's own background processes.
///
/// Processes are never terminated and never touched if `ProcessSafety` does not allow it.
/// The app cannot raise priorities (that needs root) and cannot change CPU frequency or fan speed.
public final class PriorityController {

    /// Darwin "background" state: lower CPU, disk and network priority.
    private static let backgroundState = Int32(PRIO_DARWIN_BG)
    private static let normalState: Int32 = 0

    private let lock = NSLock()
    private var lowered = Set<Int32>()
    private let isAllowed: (Int32) -> Bool
    private let stateURL: URL?

    /// - Parameters:
    ///   - isAllowed: safety check per process; defaults to `ProcessSafety`.
    ///   - stateURL: where the lowered pids are remembered. If the app crashed in quiet mode, the next launch reads
    ///     this file and puts those processes back to normal. `nil` keeps nothing on disk (tests).
    public init(isAllowed: @escaping (Int32) -> Bool = { ProcessSafety.verdict(for: $0) == .allowed },
                stateURL: URL? = nil) {
        self.isAllowed = isAllowed
        self.stateURL = stateURL
        recoverFromPreviousRun()
    }

    /// Number of processes currently held at low priority.
    public var affectedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return lowered.count
    }

    /// Makes `targets` the exact set of low-priority processes: restores others, lowers new ones.
    /// - Returns: how many processes are now lowered.
    @discardableResult
    public func reconcile(targets: Set<Int32>) -> Int {
        lock.lock()
        defer { lock.unlock() }

        for pid in lowered.subtracting(targets) {
            _ = Self.setState(Self.normalState, pid: pid)
            lowered.remove(pid)
        }
        for pid in targets.subtracting(lowered) where isAllowed(pid) {
            if Self.setState(Self.backgroundState, pid: pid) { lowered.insert(pid) }
        }
        // Drop processes that exited.
        lowered = lowered.filter { kill($0, 0) == 0 || errno == EPERM }
        persist()
        return lowered.count
    }

    /// Returns every lowered process to normal priority.
    public func restoreAll() {
        reconcile(targets: [])
    }

    // MARK: - Crash recovery

    /// Restores processes that a previous run left at low priority (it was killed or crashed in quiet mode).
    private func recoverFromPreviousRun() {
        guard let url = stateURL, let data = try? Data(contentsOf: url),
              let pids = try? JSONDecoder().decode([Int32].self, from: data) else { return }
        for pid in pids where pid > 1 { _ = Self.setState(Self.normalState, pid: pid) }
        try? FileManager.default.removeItem(at: url)
    }

    /// Called with the lock held.
    private func persist() {
        guard let url = stateURL else { return }
        if lowered.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(Array(lowered).sorted()) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func setState(_ state: Int32, pid: Int32) -> Bool {
        setpriority(PRIO_DARWIN_PROCESS, id_t(pid), state) == 0
    }
}

/// Picks which processes quiet mode should lower and which apps performance mode should suggest closing.
public enum ModePlanner {

    /// Busy background processes: everything using noticeable CPU except the app the user is working in.
    /// - Parameters:
    ///   - frontmostPID: pid of the active application; its whole group is left alone.
    ///   - minimumCPU: percent of one core below which a process is not worth touching.
    public static func quietTargets(groups: [ProcessGroup], frontmostPID: Int32?, minimumCPU: Double = 1) -> Set<Int32> {
        var targets = Set<Int32>()
        for group in groups where group.cpuPercent >= minimumCPU {
            if let front = frontmostPID, group.pids.contains(front) { continue }
            targets.formUnion(group.pids)
        }
        return targets
    }

    /// Heavy apps (other than the active one) that the user may want to close, heaviest first.
    public static func closeSuggestions(groups: [ProcessGroup], frontmostPID: Int32?,
                                        isQuittable: (ProcessGroup) -> Bool,
                                        minimumCPU: Double = 5, minimumMemory: UInt64 = 500_000_000,
                                        limit: Int = 8) -> [ProcessGroup] {
        let heavy = groups.filter { group in
            if let front = frontmostPID, group.pids.contains(front) { return false }
            return (group.cpuPercent >= minimumCPU || group.memoryBytes >= minimumMemory) && isQuittable(group)
        }
        // Busiest first; memory breaks ties (units differ, so they are not mixed into one score).
        let ranked = heavy.sorted {
            $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.memoryBytes > $1.memoryBytes
        }
        return Array(ranked.prefix(limit))
    }
}

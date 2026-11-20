//
//  DiagnosticsService.swift
//  MacControlCore
//

import Foundation

/// Tracks how long a condition has lasted. Load figures jitter, so a short dip (shorter than `grace`) does not
/// restart the count: "above 25 % for a minute" survives one low sample.
struct ConditionTimer {
    private var since: Date?
    private var inactiveSince: Date?
    private let grace: TimeInterval

    init(grace: TimeInterval = 0) {
        self.grace = grace
    }

    /// Returns how many seconds the condition has been (essentially) continuously true.
    mutating func update(_ active: Bool, now: Date) -> TimeInterval {
        if active {
            inactiveSince = nil
            if since == nil { since = now }
            return now.timeIntervalSince(since!)
        }
        guard let start = since else { return 0 }
        if inactiveSince == nil { inactiveSince = now }
        if now.timeIntervalSince(inactiveSince!) >= grace {
            since = nil
            inactiveSince = nil
            return 0
        }
        return now.timeIntervalSince(start)      // still inside the grace period
    }
}

/// Stateful wrapper around `DiagnosticsEngine`: keeps the culprit tracker and the timers
/// the rules need ("CPU above 90 % for a minute").
public final class DiagnosticsService {

    public var thresholds = DiagnosticsThresholds()

    private let culprits = CulpritTracker()
    private static let grace: TimeInterval = 20
    private var highCPU = ConditionTimer(grace: DiagnosticsService.grace)
    private var memoryPressure = ConditionTimer(grace: DiagnosticsService.grace)
    private var cooling = ConditionTimer(grace: DiagnosticsService.grace)
    private var graphics = ConditionTimer(grace: DiagnosticsService.grace)
    private var lastTimestamp: Date?

    public init() {}

    public func evaluate(snapshot: SystemSnapshot, throttle: ThrottleInfo, diskHealth: DiskHealth,
                         battery: BatteryHealth?, modelIdentifier: String, history: HistoryStore) -> [Finding] {
        let now = snapshot.timestamp
        let elapsed = min(30, max(0, lastTimestamp.map { now.timeIntervalSince($0) } ?? 0))
        lastTimestamp = now

        culprits.update(groups: snapshot.processGroups, elapsed: elapsed)

        let baseline = history.baselineTemperature(forLoad: snapshot.cpu.total)
        let windowServer = snapshot.processGroups.first { $0.processName == "WindowServer" || $0.name == "WindowServer" }
        let graphicsCPU = windowServer?.cpuPercent ?? 0
        let kernelTask = snapshot.processGroups.first { $0.processName == "kernel_task" || $0.name == "kernel_task" }
        let input = DiagnosticsInput(
            snapshot: snapshot, throttle: throttle, diskHealth: diskHealth, battery: battery,
            modelIdentifier: modelIdentifier, thresholds: thresholds,
            cpuCulprit: culprits.cpuCulprit, memoryCulprit: culprits.memoryCulprit,
            highCPUSeconds: highCPU.update(snapshot.cpu.total >= thresholds.cpuOverloadFraction, now: now),
            memoryPressureSeconds: memoryPressure.update(snapshot.memory.pressure >= .warning, now: now),
            coolingSuspicionSeconds: cooling.update(
                DiagnosticsEngine.coolingSuspected(snapshot: snapshot, baseline: baseline), now: now),
            temperatureBaseline: baseline,
            graphicsCPUPercent: graphicsCPU,
            graphicsBusySeconds: graphics.update(graphicsCPU >= DiagnosticsEngine.graphicsThreshold, now: now),
            kernelTaskCPUPercent: kernelTask?.cpuPercent ?? 0
        )
        return DiagnosticsEngine.evaluate(input)
    }
}

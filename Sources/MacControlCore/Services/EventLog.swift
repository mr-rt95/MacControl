//
//  EventLog.swift
//  MacControlCore
//

import Foundation

/// Detects and stores performance events. Thread-safe.
///
/// An event opens once its condition has held for `minimumDuration` (it is dated from the moment the
/// condition began) and closes when the condition has been false for `closeGrace` seconds.
public final class EventLog {

    // MARK: - Detector configuration

    private struct Rule {
        let kind: EventKind
        let minimumDuration: TimeInterval
    }

    private static let rules: [Rule] = [
        Rule(kind: .cpuLoad, minimumDuration: 60),
        Rule(kind: .overheating, minimumDuration: 30),
        Rule(kind: .memoryPressure, minimumDuration: 30),
        Rule(kind: .swapGrowth, minimumDuration: 0),
        Rule(kind: .diskAlmostFull, minimumDuration: 60),
        Rule(kind: .throttling, minimumDuration: 20)
    ]

    private static let closeGrace: TimeInterval = 15
    private static let swapGrowthBytes: UInt64 = 1_073_741_824
    private static let swapWindow: TimeInterval = 600

    private struct State {
        var conditionSince: Date?
        var lastActive: Date?
        var openIndex: Int?
        var scores: [String: Double] = [:]
    }

    // MARK: - Properties

    private let lock = NSLock()
    private let fileURL: URL?
    private var storedEvents: [LoggedEvent] = []
    private var states: [EventKind: State] = [:]
    private var swapSamples: [(time: Date, bytes: UInt64)] = []
    private var dirty = false

    /// Days an event is kept. Default 30.
    public var retentionDays = 30

    public init(fileURL: URL? = EventLog.defaultFileURL, now: Date = Date()) {
        self.fileURL = fileURL
        load(now: now)
    }

    /// `~/Library/Application Support/MacControl/events.json`
    public static var defaultFileURL: URL? {
        AppSupport.directory?.appendingPathComponent("events.json")
    }

    // MARK: - Reading

    /// Events, newest first.
    public var events: [LoggedEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents.sorted { $0.start > $1.start }
    }

    // MARK: - Updating

    /// Feeds a measurement. Returns `true` when the event list changed.
    @discardableResult
    public func update(snapshot: SystemSnapshot, throttle: ThrottleInfo,
                       thresholds: DiagnosticsThresholds) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = snapshot.timestamp
        let before = storedEvents
        trackSwap(snapshot.memory.swapUsed, now: now)

        for rule in Self.rules {
            let active = isActive(rule.kind, snapshot: snapshot, throttle: throttle, thresholds: thresholds)
            advance(rule, active: active, snapshot: snapshot, throttle: throttle, now: now)
        }

        let changed = storedEvents != before
        if changed { dirty = true }
        return changed
    }

    /// Removes every stored event.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        storedEvents.removeAll()
        states.removeAll()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Detection

    private func isActive(_ kind: EventKind, snapshot: SystemSnapshot, throttle: ThrottleInfo,
                          thresholds: DiagnosticsThresholds) -> Bool {
        switch kind {
        case .cpuLoad:
            return snapshot.cpu.total >= thresholds.cpuOverloadFraction
        case .overheating:
            return (snapshot.hottest(in: .cpu) ?? 0) >= thresholds.overheatingCelsius
        case .memoryPressure:
            return snapshot.memory.pressure == .critical
        case .swapGrowth:
            guard let oldest = swapSamples.map(\.bytes).min() else { return false }
            return snapshot.memory.swapUsed >= oldest + Self.swapGrowthBytes
        case .diskAlmostFull:
            let disk = snapshot.disk
            return disk.totalBytes > 0 &&
                (disk.availableBytes < thresholds.diskCriticalFreeBytes || disk.freeFraction < thresholds.diskSeriousFreeFraction)
        case .throttling:
            return throttle.isThrottling
        }
    }

    private func trackSwap(_ bytes: UInt64, now: Date) {
        swapSamples.append((now, bytes))
        swapSamples.removeAll { now.timeIntervalSince($0.time) > Self.swapWindow }
    }

    private func advance(_ rule: Rule, active: Bool, snapshot: SystemSnapshot,
                         throttle: ThrottleInfo, now: Date) {
        var state = states[rule.kind] ?? State()
        defer { states[rule.kind] = state }

        if active {
            if state.conditionSince == nil { state.conditionSince = now }
            state.lastActive = now

            let held = now.timeIntervalSince(state.conditionSince!)
            if state.openIndex == nil, held >= rule.minimumDuration {
                storedEvents.append(LoggedEvent(kind: rule.kind, start: state.conditionSince!))
                state.openIndex = storedEvents.count - 1
            }
            if let index = state.openIndex {
                for group in snapshot.processGroups where group.cpuPercent > 0.5 {
                    state.scores[group.name, default: 0] += group.cpuPercent
                }
                record(snapshot: snapshot, throttle: throttle, state: state, into: index)
            }
        } else {
            state.conditionSince = nil
            if let index = state.openIndex,
               let last = state.lastActive, now.timeIntervalSince(last) >= Self.closeGrace {
                storedEvents[index].end = last
                state.openIndex = nil
                state.scores = [:]
                prune(now: now)
                // Indices of other open events may have shifted after pruning.
                reindexOpenEvents()
            }
        }
    }

    /// Updates the peaks of an open event.
    private func record(snapshot: SystemSnapshot, throttle: ThrottleInfo, state: State, into index: Int) {
        var event = storedEvents[index]
        event.peakCPU = max(event.peakCPU, snapshot.cpu.total)
        if let temperature = snapshot.hottest(in: .cpu) {
            event.peakTemperature = max(event.peakTemperature ?? 0, temperature)
        }
        if let limit = throttle.speedLimitPercent, limit < 100 {
            event.lowestSpeedLimit = min(event.lowestSpeedLimit ?? 100, limit)
        }
        event.peakSwapBytes = max(event.peakSwapBytes ?? 0, snapshot.memory.swapUsed)
        if snapshot.disk.totalBytes > 0 {
            event.lowestFreeFraction = min(event.lowestFreeFraction ?? 1, snapshot.disk.freeFraction)
        }
        event.topProcesses = state.scores.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        storedEvents[index] = event
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        storedEvents.removeAll { !$0.isOngoing && $0.start < cutoff }
    }

    private func reindexOpenEvents() {
        for kind in EventKind.allCases {
            guard var state = states[kind], state.openIndex != nil else { continue }
            state.openIndex = storedEvents.lastIndex { $0.kind == kind && $0.isOngoing }
            states[kind] = state
        }
    }

    // MARK: - Persistence

    /// Writes the log if it changed since the last save.
    public func save() {
        lock.lock()
        let snapshot = storedEvents
        let needsSave = dirty
        dirty = false
        lock.unlock()

        guard needsSave, let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func load(now: Date) {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard var loaded = try? decoder.decode([LoggedEvent].self, from: data) else { return }
        // An event left open by a quit or crash ends at the moment of loading.
        for index in loaded.indices where loaded[index].isOngoing { loaded[index].end = loaded[index].start }
        storedEvents = loaded
        prune(now: now)
    }
}

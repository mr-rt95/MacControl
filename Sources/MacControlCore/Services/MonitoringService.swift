//
//  MonitoringService.swift
//  MacControlCore
//

import Foundation
import Combine

/// How often the service samples the system.
public enum PollingMode: Equatable {
    /// A window is visible: refresh every second.
    case foreground
    /// Only the menu bar item is alive: refresh rarely to keep CPU use near zero.
    case background

    public var interval: TimeInterval {
        switch self {
        case .foreground: return 1
        case .background: return 5
        }
    }
}

/// Periodically samples the system on a background queue and publishes the results on the main queue.
public final class MonitoringService: ObservableObject {

    @Published public private(set) var snapshot: SystemSnapshot?
    /// Short in-memory series for live sparklines.
    @Published public private(set) var history = MetricHistory()
    /// Findings, throttling state, battery and SSD health.
    @Published public private(set) var analysis = AnalysisResult()
    /// Event journal, newest first.
    @Published public private(set) var events: [LoggedEvent] = []

    /// Long-term (hour/day/week) history; safe to read from any thread.
    public let historyStore: HistoryStore
    public let eventLog: EventLog

    public let modelIdentifier: String
    public let sensorsAvailable: Bool

    /// Supplies processes only an administrator can see (set once the helper is available). Runs on the sampling queue.
    public var supplementalProcesses: (() -> [ProcessSample])? {
        get { queue.sync { sampler.supplementalProcesses } }
        set { queue.async { [weak self] in self?.sampler.supplementalProcesses = newValue } }
    }

    private let sampler: SystemSampler
    private let diagnostics = DiagnosticsService()
    private let throttleMonitor = ThrottleMonitor()
    private let batteryMonitor = BatteryMonitor()
    private let diskHealthMonitor = DiskHealthMonitor()

    private static let batteryRefresh: TimeInterval = 60
    private static let diskHealthRefresh: TimeInterval = 1_800
    private static let saveInterval: TimeInterval = 300

    private var battery: BatteryHealth?
    private var diskHealth = DiskHealth.unknown
    private var lastBatteryRead = Date.distantPast
    private var lastDiskHealthRead = Date.distantPast
    private var lastSave = Date()
    private let queue = DispatchQueue(label: "com.maccontrol.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var mode: PollingMode = .background

    public init(sampler: SystemSampler = SystemSampler(),
                historyStore: HistoryStore = HistoryStore(),
                eventLog: EventLog = EventLog()) {
        self.sampler = sampler
        self.historyStore = historyStore
        self.eventLog = eventLog
        self.events = eventLog.events
        self.modelIdentifier = sampler.modelIdentifier
        self.sensorsAvailable = sampler.sensorsAvailable
    }

    deinit { timer?.cancel() }

    /// Starts periodic sampling. Calling it again has no effect.
    public func start() {
        queue.async { [weak self] in
            guard let self = self, self.timer == nil else { return }
            self.scheduleTimer()
        }
    }

    /// Stops sampling.
    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// Switches between fast (window visible) and slow (menu bar only) refresh.
    public func setMode(_ newMode: PollingMode) {
        queue.async { [weak self] in
            guard let self = self, self.mode != newMode else { return }
            self.mode = newMode
            guard self.timer != nil else { return }
            self.timer?.cancel()
            self.scheduleTimer()
            self.tick()   // refresh immediately so the window does not show stale data
        }
    }

    /// Applies user-adjustable limits and the journal retention period.
    public func configure(thresholds: DiagnosticsThresholds, retentionDays: Int) {
        queue.async { [weak self] in
            self?.diagnostics.thresholds = thresholds
            self?.eventLog.retentionDays = retentionDays
        }
    }

    /// Writes history and journal to disk (call before the app quits).
    public func flush() {
        queue.sync {
            historyStore.save()
            eventLog.save()
        }
    }

    /// Deletes stored history (graphs and cooling baseline).
    public func clearHistory() {
        queue.async { [weak self] in self?.historyStore.clear() }
    }

    /// Deletes the event journal.
    public func clearEvents() {
        queue.async { [weak self] in
            self?.eventLog.clear()
            DispatchQueue.main.async { self?.events = [] }
        }
    }

    // MARK: - Private (runs on `queue`)

    private func scheduleTimer() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: mode.interval, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    private func tick() {
        let snapshot = sampler.sample()
        let now = snapshot.timestamp

        refreshSlowData(now: now)
        let throttle = throttleMonitor.current(now: now)

        historyStore.record(snapshot)
        let eventsChanged = eventLog.update(snapshot: snapshot, throttle: throttle,
                                            thresholds: diagnostics.thresholds)

        var result = AnalysisResult()
        result.throttle = throttle
        result.battery = battery
        result.diskHealth = diskHealth
        result.findings = diagnostics.evaluate(snapshot: snapshot, throttle: throttle, diskHealth: diskHealth,
                                               battery: battery, modelIdentifier: modelIdentifier,
                                               history: historyStore)

        if now.timeIntervalSince(lastSave) >= Self.saveInterval {
            lastSave = now
            historyStore.save()
            eventLog.save()
        }

        let events = eventsChanged ? eventLog.events : nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.history.record(snapshot)
            self.snapshot = snapshot
            if self.analysis != result { self.analysis = result }
            if let events = events { self.events = events }
        }
    }

    /// Battery and SSD status change slowly, so they are re-read only now and then.
    private func refreshSlowData(now: Date) {
        if now.timeIntervalSince(lastBatteryRead) >= Self.batteryRefresh {
            lastBatteryRead = now
            battery = batteryMonitor.read()
        }
        if now.timeIntervalSince(lastDiskHealthRead) >= Self.diskHealthRefresh {
            lastDiskHealthRead = now
            diskHealth = diskHealthMonitor.read()
        }
    }
}

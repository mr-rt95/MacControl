//
//  SystemReport.swift
//  MacControlCore
//

import Foundation

/// A finding already worded for a human reader.
public struct ReportFinding: Equatable {
    public let severity: Severity
    public let title: String
    public let detail: String
    public let advice: String
    public let evidence: [Evidence]

    public init(severity: Severity, title: String, detail: String, advice: String, evidence: [Evidence]) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.advice = advice
        self.evidence = evidence
    }
}

/// An application and its load. Application names only: no file names or paths.
public struct ReportProcess: Equatable {
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public init(name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

/// Everything that goes into the exported report.
///
/// Privacy: it holds hardware facts, load figures, application names and startup item labels, never
/// file names, document contents, user names or paths.
public struct SystemReport {

    public var generated = Date()
    public var modelIdentifier = ""
    public var osVersion = ""
    public var logicalCores = 0
    public var uptime: TimeInterval = 0

    public var memory: MemoryStats = .empty
    public var disk: DiskStats = .empty
    public var diskHealth: DiskHealth = .unknown
    public var battery: BatteryHealth?
    public var throttle: ThrottleInfo = .none
    public var temperatures: [TemperatureReading] = []
    public var fans: [FanReading] = []

    public var findings: [ReportFinding] = []
    public var topProcesses: [ReportProcess] = []
    /// Labels of third-party items that start automatically.
    public var startupItems: [String] = []
    /// Journal entries of the last 24 hours.
    public var recentEvents: [LoggedEvent] = []

    public init() {}

    /// Fills the static facts about this Mac.
    public mutating func collectSystemFacts() {
        generated = Date()
        modelIdentifier = Sysctl.string("hw.model") ?? ""
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        logicalCores = ProcessInfo.processInfo.processorCount
        uptime = ProcessInfo.processInfo.systemUptime
    }

    /// Takes the heaviest applications from process groups.
    public static func processes(from groups: [ProcessGroup], limit: Int = 10) -> [ReportProcess] {
        groups.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit).map {
            ReportProcess(name: $0.name, cpuPercent: $0.cpuPercent, memoryBytes: $0.memoryBytes)
        }
    }
}

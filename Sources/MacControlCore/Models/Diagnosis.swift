//
//  Diagnosis.swift
//  MacControlCore
//

import Foundation

/// What a diagnostic finding is about. The UI layer owns the wording (see `FindingPresenter`),
/// so the core stays language-independent.
public enum FindingKind: String, Codable, CaseIterable {
    case overheating
    case throttling
    case cpuOverload
    case memoryPressure
    case diskLow
    case cooling
    case graphicsLoad
    case ssdFailing
    case ssdWear
    case batteryWear

    /// Lower value = listed first among findings of equal severity.
    var priority: Int {
        switch self {
        case .overheating: return 0
        case .throttling: return 1
        case .ssdFailing: return 2
        case .ssdWear: return 8
        case .memoryPressure: return 3
        case .diskLow: return 4
        case .cpuOverload: return 5
        case .cooling: return 6
        case .graphicsLoad: return 5
        case .batteryWear: return 7
        }
    }
}

public enum Severity: Int, Comparable, Equatable {
    case info = 0, warning, serious, critical

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What the user is advised to do about a finding.
public enum RecommendedAction: Equatable {
    case quitApp(name: String)
    case closeHeavyApps
    case freeDiskSpace
    case cleanCooling
    case reduceMemoryUse
    case addMemory
    case replaceBattery
    case planSSDReplacement
    case reduceVisualEffects
    case backUpData
}

/// The application most likely responsible for a problem.
public struct Culprit: Equatable {
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    /// How long the application has been continuously busy.
    public let activeSeconds: TimeInterval

    public init(name: String, cpuPercent: Double, memoryBytes: UInt64, activeSeconds: TimeInterval) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.activeSeconds = activeSeconds
    }
}

/// One measurement a conclusion is based on ("Show data").
public struct Evidence: Equatable, Identifiable {
    /// English label, used as a localization key.
    public let label: String
    public let value: String
    public var id: String { label }

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// A conclusion of the rule engine. Always carries the data it is based on.
public struct Finding: Identifiable, Equatable {

    public let kind: FindingKind
    public let severity: Severity
    public let culprit: Culprit?
    /// Raw numbers used to fill message templates.
    public let metrics: [String: Double]
    public let evidence: [Evidence]
    public let action: RecommendedAction

    public var id: String { kind.rawValue }

    public init(kind: FindingKind, severity: Severity, culprit: Culprit? = nil,
                metrics: [String: Double] = [:], evidence: [Evidence] = [], action: RecommendedAction) {
        self.kind = kind
        self.severity = severity
        self.culprit = culprit
        self.metrics = metrics
        self.evidence = evidence
        self.action = action
    }
}

/// User-adjustable limits for the rule engine.
public struct DiagnosticsThresholds: Equatable {
    public var diskWarningFreeFraction = 0.15
    public var diskSeriousFreeFraction = 0.10
    public var diskCriticalFreeBytes: UInt64 = 10 * 1_073_741_824
    public var cpuOverloadFraction = 0.9
    public var cpuOverloadSeconds: TimeInterval = 60
    public var overheatingCelsius = 90.0

    public init() {}
}

/// Everything the UI shows besides raw metrics.
public struct AnalysisResult: Equatable {
    public var findings: [Finding] = []
    public var throttle: ThrottleInfo = .none
    public var battery: BatteryHealth?
    public var diskHealth: DiskHealth = .unknown

    public init() {}
}

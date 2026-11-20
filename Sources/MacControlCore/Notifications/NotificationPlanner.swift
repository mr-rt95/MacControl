//
//  NotificationPlanner.swift
//  MacControlCore
//

import Foundation

/// Situations the user can be notified about.
public enum AlertKind: String, CaseIterable, Codable, Identifiable {
    case overheating
    case lowDisk
    case memoryPressure
    case frozenApp
    case longHighLoad

    public var id: String { rawValue }
}

/// A notification the app should show now. Wording is added by the UI layer.
public struct PlannedAlert: Equatable {
    public let kind: AlertKind
    public let severity: Severity
    /// Application involved (frozen app, main consumer), if any.
    public let appName: String?
    /// Raw numbers for the message template (temperature, free bytes, load, duration, …).
    public let metrics: [String: Double]
}

/// Decides which findings deserve a notification, and suppresses repeats.
///
/// A notification for a kind is sent again only after `cooldown` has passed, or at once when the
/// situation gets worse. A kind that disappears for `quietPeriod` starts a fresh episode.
public final class NotificationPlanner {

    /// Sustained near-full CPU use of one app before it is called possibly frozen.
    public static let frozenAfter: TimeInterval = 180
    /// Sustained high overall load before the user is told about it.
    public static let longLoadAfter: TimeInterval = 300

    public var cooldown: TimeInterval
    private let quietPeriod: TimeInterval

    private var lastSent: [AlertKind: (date: Date, severity: Severity)] = [:]
    private var lastActive: [AlertKind: Date] = [:]

    public init(cooldown: TimeInterval = 1_800, quietPeriod: TimeInterval = 600) {
        self.cooldown = cooldown
        self.quietPeriod = quietPeriod
    }

    /// - Parameters:
    ///   - findings: current diagnostic findings.
    ///   - enabled: kinds the user wants to hear about.
    public func plan(findings: [Finding], enabled: Set<AlertKind>, now: Date = Date()) -> [PlannedAlert] {
        let candidates = Self.candidates(from: findings)
        for candidate in candidates { lastActive[candidate.kind] = now }

        // Forget episodes that ended long ago so the next one is announced again.
        for (kind, date) in lastActive where now.timeIntervalSince(date) > quietPeriod {
            lastSent[kind] = nil
            lastActive[kind] = nil
        }

        var result: [PlannedAlert] = []
        for alert in candidates where enabled.contains(alert.kind) {
            if let previous = lastSent[alert.kind] {
                let worse = alert.severity > previous.severity
                guard worse || now.timeIntervalSince(previous.date) >= cooldown else { continue }
            }
            lastSent[alert.kind] = (now, alert.severity)
            result.append(alert)
        }
        return result
    }

    // MARK: - Mapping (pure, unit-tested)

    static func candidates(from findings: [Finding]) -> [PlannedAlert] {
        var alerts: [PlannedAlert] = []

        for finding in findings {
            switch finding.kind {
            case .overheating, .throttling:
                alerts.append(PlannedAlert(kind: .overheating, severity: finding.severity,
                                           appName: finding.culprit?.name, metrics: finding.metrics))
            case .diskLow:
                alerts.append(PlannedAlert(kind: .lowDisk, severity: finding.severity, appName: nil, metrics: finding.metrics))
            case .memoryPressure:
                alerts.append(PlannedAlert(kind: .memoryPressure, severity: finding.severity,
                                           appName: finding.culprit?.name, metrics: finding.metrics))
            case .cpuOverload:
                if let culprit = finding.culprit, culprit.cpuPercent >= 95, culprit.activeSeconds >= frozenAfter {
                    alerts.append(PlannedAlert(kind: .frozenApp, severity: .warning, appName: culprit.name,
                                               metrics: ["duration": culprit.activeSeconds, "cpu": culprit.cpuPercent]))
                }
                if (finding.metrics["duration"] ?? 0) >= longLoadAfter {
                    alerts.append(PlannedAlert(kind: .longHighLoad, severity: .info,
                                               appName: finding.culprit?.name, metrics: finding.metrics))
                }
            case .cooling, .graphicsLoad, .ssdFailing, .ssdWear, .batteryWear:
                break   // shown in the app; not urgent enough to interrupt the user
            }
        }
        return alerts
    }
}

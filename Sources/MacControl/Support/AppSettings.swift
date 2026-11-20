//
//  AppSettings.swift
//  MacControl
//

import Foundation
import Combine
import MacControlCore

/// User preferences persisted in `UserDefaults`.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum Key {
        static let menuBarTemperature = "menuBar.showTemperature"
        static let menuBarCPU = "menuBar.showCPU"
        static let menuBarMemory = "menuBar.showMemory"
        static let diskWarningPercent = "diagnostics.diskWarningPercent"
        static let retentionDays = "journal.retentionDays"
        static let notificationsEnabled = "notifications.enabled"
        static let cooldownMinutes = "notifications.cooldownMinutes"
        static func alert(_ kind: AlertKind) -> String { "notifications.kind.\(kind.rawValue)" }
    }

    private let defaults: UserDefaults

    @Published var menuBarShowsTemperature: Bool {
        didSet { defaults.set(menuBarShowsTemperature, forKey: Key.menuBarTemperature) }
    }
    @Published var menuBarShowsCPU: Bool {
        didSet { defaults.set(menuBarShowsCPU, forKey: Key.menuBarCPU) }
    }
    @Published var menuBarShowsMemory: Bool {
        didSet { defaults.set(menuBarShowsMemory, forKey: Key.menuBarMemory) }
    }
    /// Free-space percentage below which the disk is reported as filling up.
    @Published var diskWarningPercent: Int {
        didSet { defaults.set(diskWarningPercent, forKey: Key.diskWarningPercent) }
    }
    /// Days the event journal is kept.
    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Key.retentionDays) }
    }
    /// Master switch for system notifications (off until the user turns it on and macOS permits it).
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }
    /// Minimum minutes before the same kind of notification is repeated.
    @Published var notificationCooldownMinutes: Int {
        didSet { defaults.set(notificationCooldownMinutes, forKey: Key.cooldownMinutes) }
    }
    @Published private var disabledAlertKinds: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.menuBarTemperature: true,
            Key.menuBarCPU: true,
            Key.menuBarMemory: false,
            Key.diskWarningPercent: 15,
            Key.retentionDays: 30,
            Key.notificationsEnabled: false,
            Key.cooldownMinutes: 30
        ])
        menuBarShowsTemperature = defaults.bool(forKey: Key.menuBarTemperature)
        menuBarShowsCPU = defaults.bool(forKey: Key.menuBarCPU)
        menuBarShowsMemory = defaults.bool(forKey: Key.menuBarMemory)
        diskWarningPercent = defaults.integer(forKey: Key.diskWarningPercent)
        retentionDays = defaults.integer(forKey: Key.retentionDays)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        notificationCooldownMinutes = defaults.integer(forKey: Key.cooldownMinutes)
        disabledAlertKinds = Set(AlertKind.allCases.map(\.rawValue).filter { defaults.object(forKey: Key.alert(AlertKind(rawValue: $0)!)) as? Bool == false })
    }

    func isAlertEnabled(_ kind: AlertKind) -> Bool { !disabledAlertKinds.contains(kind.rawValue) }

    func setAlert(_ kind: AlertKind, enabled: Bool) {
        if enabled { disabledAlertKinds.remove(kind.rawValue) } else { disabledAlertKinds.insert(kind.rawValue) }
        defaults.set(enabled, forKey: Key.alert(kind))
    }

    var enabledAlertKinds: Set<AlertKind> { Set(AlertKind.allCases.filter(isAlertEnabled)) }
}

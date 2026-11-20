//
//  SettingsView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Preferences window (⌘,).
struct SettingsView: View {

    @ObservedObject var settings: AppSettings
    let monitoring: MonitoringService
    let notifications: NotificationService
    @ObservedObject var launchAtLogin: LoginLaunchService
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Temperature", isOn: $settings.menuBarShowsTemperature)
                Toggle("Processor load", isOn: $settings.menuBarShowsCPU)
                Toggle("Memory usage", isOn: $settings.menuBarShowsMemory)
            } header: {
                Text("Menu bar shows").font(.headline)
            }

            Section {
                Toggle("Launch MacControl at login", isOn: Binding(get: { launchAtLogin.isEnabled },
                                                                  set: { launchAtLogin.setEnabled($0) }))
            } header: {
                Text("General").font(.headline)
            }

            Section {
                Toggle("Show notifications", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { enableNotifications($0) }))
                if notificationsDenied {
                    Text("Notifications are blocked. Allow them in System Settings ▸ Notifications.")
                        .font(.caption).foregroundColor(Palette.warning)
                }
                ForEach(AlertKind.allCases) { kind in
                    Toggle(Self.title(kind), isOn: Binding(get: { settings.isAlertEnabled(kind) },
                                                            set: { settings.setAlert(kind, enabled: $0) }))
                        .disabled(!settings.notificationsEnabled)
                }
                Picker("Repeat the same notification no sooner than", selection: $settings.notificationCooldownMinutes) {
                    ForEach([10, 30, 60, 180], id: \.self) { Text(verbatim: tr("%@ min", "\($0)")).tag($0) }
                }
                .disabled(!settings.notificationsEnabled)
            } header: {
                Text("Notifications").font(.headline)
            }

            Section {
                Picker("Warn when free disk space is below", selection: $settings.diskWarningPercent) {
                    ForEach([10, 15, 20, 25], id: \.self) { Text(verbatim: "\($0)%").tag($0) }
                }
                Picker("Keep the journal for", selection: $settings.retentionDays) {
                    ForEach([7, 14, 30, 90], id: \.self) { Text(verbatim: tr("%@ days", "\($0)")).tag($0) }
                }
            } header: {
                Text("Diagnostics").font(.headline)
            }

            Section {
                HStack {
                    Button("Clear history") { monitoring.clearHistory() }
                    Button("Clear journal") { monitoring.clearEvents() }
                }
            } header: {
                Text("Data").font(.headline)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    /// Turning notifications on asks macOS for permission first.
    private func enableNotifications(_ on: Bool) {
        guard on else { settings.notificationsEnabled = false; return }
        notifications.requestAuthorization { granted in
            notificationsDenied = !granted
            settings.notificationsEnabled = granted
        }
    }

    private static func title(_ kind: AlertKind) -> LocalizedStringKey {
        switch kind {
        case .overheating:     return "Overheating"
        case .lowDisk:         return "Disk almost full"
        case .memoryPressure:  return "Critical memory pressure"
        case .frozenApp:       return "An app may be frozen"
        case .longHighLoad:    return "Long high processor load"
        }
    }
}

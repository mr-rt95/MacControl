//
//  StartupView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Programs that start at login and the background services that keep running.
struct StartupView: View {

    enum Tab { case startup, services, loginItems }

    let groups: [ProcessGroup]
    @ObservedObject var model: StartupViewModel
    @State private var tab = Tab.startup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                Text("Startup items").tag(Tab.startup)
                Text("Background services").tag(Tab.services)
                Text("Login items").tag(Tab.loginItems)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)

            switch tab {
            case .startup:    startupList
            case .services:   servicesList
            case .loginItems: loginItemsList
            }
        }
        .banner($model.banner)
        .onAppear { model.refresh(groups: groups) }
    }

    // MARK: - Startup items

    private var startupList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Disabling keeps the file and can be undone. Items outside your user folder and Apple services are read-only here.")
                .font(.caption).foregroundColor(.secondary)
            let items = model.items.filter { $0.scope != .system && ($0.runsAtLoad || $0.keepsAlive || $0.isRunning) }
            if items.isEmpty && !model.isLoading { Text("Nothing starts automatically.").foregroundColor(.secondary) }
            ForEach(items) { item in row(item, showToggle: true) }
        }
    }

    private var servicesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Running launchd services, heaviest first. Apple's services are shown for information only.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(model.heavyServices.prefix(60)) { item in row(item, showToggle: item.scope != .system && !item.isApple) }
            if model.heavyServices.isEmpty && !model.isLoading { Text("No services found.").foregroundColor(.secondary) }
        }
    }

    private func row(_ item: LaunchItem, showToggle: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: item.label).font(.headline).lineLimit(1).truncationMode(.middle)
                    safetyBadge(item.safety)
                }
                if let summary = ServiceKnowledge.info(for: item.label)?.summary {
                    Text(verbatim: tr(summary)).font(.callout)
                }
                Text(verbatim: details(item)).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if showToggle && !item.isApple {
                Toggle("", isOn: Binding(get: { !item.isDisabled },
                                         set: { model.setEnabled($0, item: item, groups: groups) }))
                    .labelsHidden()
                    .disabled(item.scope.requiresAdministrator && !model.helperUsable)
                    .help(item.scope.requiresAdministrator && !model.helperUsable ? tr("Needs administrator rights") : "")
            } else {
                Image(systemName: "lock.fill").foregroundColor(.secondary).font(.caption)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.cardBackground))
    }

    private func details(_ item: LaunchItem) -> String {
        var parts = [tr("Impact: %@", Self.impactText(item.impact))]
        if item.isRunning { parts.append("\(Formatters.cpuPercent(item.cpuPercent)) · \(Formatters.bytes(item.memoryBytes))") }
        switch item.scope {
        case .userAgent: break
        case .globalAgent, .globalDaemon: parts.append(tr("System-wide"))
        case .system: parts.append(tr("macOS"))
        }
        return parts.joined(separator: " · ")
    }

    private func safetyBadge(_ safety: ServiceSafety) -> some View {
        let (text, color): (LocalizedStringKey, Color) = {
            switch safety {
            case .safe:    return ("Safe to stop", Palette.good)
            case .caution: return ("Use caution", Palette.warning)
            case .system:  return ("System", .secondary)
            case .unknown: return ("Unknown", .secondary)
            }
        }()
        return Text(text).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18))).foregroundColor(color)
    }

    private static func impactText(_ impact: StartupImpact) -> String {
        switch impact {
        case .low: return tr("low")
        case .medium: return tr("medium")
        case .high: return tr("high")
        }
    }

    // MARK: - Login items

    private var loginItemsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These come from System Settings ▸ General ▸ Login Items. macOS asks permission to read them.")
                .font(.caption).foregroundColor(.secondary)
            if !model.loginItemsLoaded {
                Button("Show login items") { model.loadLoginItems() }
            } else {
                if model.loginItems.isEmpty { Text("No login items.").foregroundColor(.secondary) }
                ForEach(model.loginItems) { item in
                    HStack {
                        Text(verbatim: item.name)
                        Spacer()
                        Button("Remove from login") { model.removeLoginItem(item) }
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Palette.cardBackground))
                }
            }
            if !model.removedLoginItems.isEmpty {
                Text("Removed by MacControl").font(.headline).padding(.top, 8)
                ForEach(model.removedLoginItems) { item in
                    HStack {
                        Text(verbatim: item.name).foregroundColor(.secondary)
                        Spacer()
                        Button("Put back") { model.restoreLoginItem(item) }
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Palette.cardBackground))
                }
            }
        }
    }
}

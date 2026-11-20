//
//  MenuBarSummaryView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Content of the popover shown when the menu bar item is clicked.
struct MenuBarSummaryView: View {

    @ObservedObject var monitoring: MonitoringService
    @ObservedObject var modes: ModesViewModel
    let openApp: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = monitoring.snapshot {
                headline
                summary(snapshot)
                Divider()
                topProcesses(snapshot)
            } else {
                Text("Collecting data…").foregroundColor(.secondary)
            }
            Divider()
            Picker("", selection: Binding(get: { modes.mode }, set: { modes.setMode($0) })) {
                Text("Normal").tag(PerformanceMode.normal)
                Text("Quiet").tag(PerformanceMode.quiet)
                Text("Performance").tag(PerformanceMode.performance)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Divider()
            HStack {
                Button("Open MacControl", action: openApp)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Quit", action: quit)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// One-line verdict: the most serious finding, or "everything is fine".
    private var headline: some View {
        let finding = monitoring.analysis.findings.first
        return HStack(spacing: 8) {
            Image(systemName: finding?.severity.symbol ?? "checkmark.seal.fill")
                .foregroundColor(finding?.severity.color ?? Palette.good)
            Text(verbatim: finding.map { FindingPresenter.text(for: $0).title } ?? tr("Everything is fine"))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summary(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Processor", value: Formatters.percent(snapshot.cpu.total),
                color: Palette.color(forLoad: snapshot.cpu.total))
            row("Memory", value: "\(Formatters.bytes(snapshot.memory.used)) / \(Formatters.bytes(snapshot.memory.total))",
                color: Palette.color(for: snapshot.memory.pressure))
            if let temperature = snapshot.cpuTemperature {
                row("Temperature", value: Formatters.temperature(temperature),
                    color: Palette.color(for: ThermalLevel.classify(celsius: temperature, category: .cpu)))
            }
            if let rpm = snapshot.fans.first?.currentRPM {
                row("Fan", value: tr("%@ rpm", Formatters.rpm(rpm)), color: .primary)
            }
            row("Disk", value: tr("%@ free", Formatters.bytes(snapshot.disk.availableBytes)),
                color: Palette.color(forLoad: snapshot.disk.usedFraction))
        }
    }

    private func topProcesses(_ snapshot: SystemSnapshot) -> some View {
        let top = snapshot.processGroups.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Top consumers").font(.caption).foregroundColor(.secondary)
            ForEach(Array(top)) { group in
                HStack {
                    Text(verbatim: group.name).lineLimit(1)
                    Spacer()
                    Text(verbatim: Formatters.cpuPercent(group.cpuPercent)).monospacedDigit().foregroundColor(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(verbatim: value).monospacedDigit().foregroundColor(color)
        }
    }
}

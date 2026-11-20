//
//  ProcessorView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Total and per-core CPU load, thermal throttling state and the heaviest apps.
struct ProcessorView: View {

    let snapshot: SystemSnapshot
    let history: MetricHistory
    let throttle: ThrottleInfo
    @ObservedObject var helper: HelperManager

    private let coreColumns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    /// Shown next to the limit: how much the CPU is held back, with the temperature and load at this moment.
    private var throttleCaption: String? {
        guard let limit = throttle.speedLimitPercent else { return tr("No data") }
        let state = limit < 100
            ? tr("Throttled to %@ of maximum", "\(limit)%")
            : tr("Running at full speed")
        guard let temperature = snapshot.cpuTemperature else { return state }
        return "\(state) · \(Formatters.temperature(temperature)) · \(Formatters.percent(snapshot.cpu.total))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                MetricCard(title: "Total load",
                           value: Formatters.percent(snapshot.cpu.total),
                           caption: nil,
                           tint: Palette.color(forLoad: snapshot.cpu.total)) {
                    Sparkline(values: history.cpu.elements, maximum: 1,
                              color: Palette.color(forLoad: snapshot.cpu.total))
                        .frame(height: 60)
                }
                MetricCard(title: "User / System",
                           value: "\(Formatters.percent(snapshot.cpu.user)) / \(Formatters.percent(snapshot.cpu.system))",
                           caption: nil)
                MetricCard(title: "Speed limit",
                           value: throttle.speedLimitPercent.map { "\($0)%" } ?? "—",
                           caption: throttleCaption,
                           tint: throttle.isThrottling ? Palette.critical : Palette.good) {
                    HStack(spacing: 8) {
                        Circle().fill(Palette.color(for: snapshot.thermalState)).frame(width: 10, height: 10)
                        Text(snapshot.thermalState.title).font(.callout)
                    }
                }
            }

            ExtendedCPUCard(helper: helper)

            Text("Cores").font(.headline)
            LazyVGrid(columns: coreColumns, spacing: 12) {
                ForEach(Array(snapshot.cpu.perCore.enumerated()), id: \.offset) { index, load in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: "\(index + 1)").foregroundColor(.secondary)
                            Spacer()
                            Text(verbatim: Formatters.percent(load)).monospacedDigit()
                        }
                        .font(.caption)
                        ProgressBar(fraction: load, color: Palette.color(forLoad: load))
                    }
                }
            }

            Text("Top consumers").font(.headline)
            ProcessTable(groups: snapshot.processGroups,
                         initialSort: KeyPathComparator(\ProcessGroup.cpuPercent, order: .reverse))
        }
    }
}

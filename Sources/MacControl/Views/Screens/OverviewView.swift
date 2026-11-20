//
//  OverviewView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Dashboard: one card per subsystem plus the busiest applications.
struct OverviewView: View {

    let snapshot: SystemSnapshot
    let history: MetricHistory
    let analysis: AnalysisResult
    let navigate: (Screen) -> Void

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 14, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let headline = analysis.findings.first {
                FindingCard(finding: headline, navigate: navigate)
            }
            LazyVGrid(columns: columns, spacing: 14) {
                MetricCard(title: "Processor",
                           value: Formatters.percent(snapshot.cpu.total),
                           caption: nil,
                           tint: Palette.color(forLoad: snapshot.cpu.total)) {
                    Sparkline(values: history.cpu.elements, maximum: 1, color: Palette.color(forLoad: snapshot.cpu.total))
                        .frame(height: 40)
                }

                MetricCard(title: "Memory",
                           value: Formatters.percent(snapshot.memory.usedFraction),
                           caption: "\(Formatters.bytes(snapshot.memory.used)) / \(Formatters.bytes(snapshot.memory.total))",
                           tint: Palette.color(for: snapshot.memory.pressure)) {
                    Sparkline(values: history.memory.elements, maximum: 1, color: Palette.color(for: snapshot.memory.pressure))
                        .frame(height: 40)
                }

                MetricCard(title: "Disk",
                           value: Formatters.bytes(snapshot.disk.availableBytes),
                           caption: nil) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressBar(fraction: snapshot.disk.usedFraction,
                                    color: Palette.color(forLoad: snapshot.disk.usedFraction))
                        Text(verbatim: "↓ \(Formatters.rate(snapshot.disk.readBytesPerSecond))   ↑ \(Formatters.rate(snapshot.disk.writeBytesPerSecond))")
                            .font(.caption).monospacedDigit().foregroundColor(.secondary)
                    }
                }

                MetricCard(title: "Network",
                           value: "↓ \(Formatters.rate(snapshot.network.downloadBytesPerSecond))",
                           caption: "↑ \(Formatters.rate(snapshot.network.uploadBytesPerSecond))") {
                    Sparkline(values: history.networkDown.elements, color: .blue)
                        .frame(height: 40)
                }

                temperatureCard
                fanCard
            }

            Text("Busiest apps")
                .font(.headline)
            ProcessTable(groups: snapshot.processGroups,
                         initialSort: KeyPathComparator(\ProcessGroup.cpuPercent, order: .reverse))
        }
    }

    @ViewBuilder
    private var temperatureCard: some View {
        if let temperature = snapshot.cpuTemperature {
            let level = ThermalLevel.classify(celsius: temperature, category: .cpu)
            MetricCard(title: "Temperature",
                       value: Formatters.temperature(temperature),
                       tint: Palette.color(for: level)) {
                Sparkline(values: history.cpuTemperature.elements, maximum: 110, color: Palette.color(for: level))
                    .frame(height: 40)
            }
        } else {
            MetricCard(title: "Temperature", value: "—", caption: tr("No data"))
        }
    }

    @ViewBuilder
    private var fanCard: some View {
        if let fan = snapshot.fans.first, let rpm = fan.currentRPM {
            MetricCard(title: "Fan", value: tr("%@ rpm", Formatters.rpm(rpm)),
                       caption: nil) {
                ProgressBar(fraction: fan.speedFraction ?? 0, color: .teal)
            }
        } else {
            MetricCard(title: "Fan", value: "—", caption: tr("No data"))
        }
    }
}

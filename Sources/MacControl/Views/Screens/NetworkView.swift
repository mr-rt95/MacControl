//
//  NetworkView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Aggregate throughput and per-process traffic. `nettop` only runs while this screen is visible.
struct NetworkView: View {

    let snapshot: SystemSnapshot
    let history: MetricHistory

    @StateObject private var processService = NetworkProcessService()

    /// `nettop` truncates names ("Brave Browser H"); the process list has the full application name.
    private func displayName(for item: ProcessNetworkUsage) -> String {
        snapshot.processGroups.first { $0.pids.contains(item.pid) }?.name ?? item.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                MetricCard(title: "Download", value: Formatters.rate(snapshot.network.downloadBytesPerSecond)) {
                    Sparkline(values: history.networkDown.elements, color: .blue).frame(height: 50)
                }
                MetricCard(title: "Upload", value: Formatters.rate(snapshot.network.uploadBytesPerSecond)) {
                    Sparkline(values: history.networkUp.elements, color: .green).frame(height: 50)
                }
            }

            Text("Traffic by process").font(.headline)
            if !processService.hasMeasurement {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").foregroundColor(.secondary)
                }
            } else if processService.usage.isEmpty {
                Text("No network activity detected.").foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(processService.usage.prefix(25)) { item in
                        HStack {
                            Text(verbatim: displayName(for: item)).lineLimit(1)
                            Spacer()
                            Text(verbatim: "↓ \(Formatters.bytes(item.bytesIn))   ↑ \(Formatters.bytes(item.bytesOut))")
                                .monospacedDigit().foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
                Text("Traffic during the last measurement window. Depends on what the system tool nettop reports.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .onAppear { processService.start() }
        .onDisappear { processService.stop() }
    }
}

//
//  HistoryView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Hour / day / week charts of load and temperature with a hover read-out.
struct HistoryView: View {

    let store: HistoryStore
    /// Changes every sample, which refreshes the charts.
    let refreshToken: Date

    @State private var range: HistoryRange = .hour
    @State private var hoverDate: Date?

    var body: some View {
        let now = refreshToken
        let interval = DateInterval(start: now.addingTimeInterval(-range.span), end: now)
        let points = store.points(for: range, now: now)

        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $range) {
                Text("Hour").tag(HistoryRange.hour)
                Text("Day").tag(HistoryRange.day)
                Text("Week").tag(HistoryRange.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            readout(points: points)

            if points.count < 2 {
                Text("Not enough data yet. Charts fill in as MacControl keeps running.")
                    .foregroundColor(.secondary)
            }

            chart("Processor", points, interval, maximum: 1, format: Formatters.percent,
                  [ChartSeries(id: "cpu", title: "Processor", color: .blue, value: { $0.cpu })])
            chart("Memory", points, interval, maximum: 1, format: Formatters.percent,
                  [ChartSeries(id: "mem", title: "Used", color: .purple, value: { $0.memory })])
            chart("Temperature", points, interval, maximum: 110, format: Formatters.temperature,
                  [ChartSeries(id: "temp", title: "Processor", color: .red, value: { $0.cpuTemperature })])
            chart("Disk", points, interval, maximum: nil, format: Formatters.rate,
                  [ChartSeries(id: "r", title: "Read", color: .blue, value: { $0.diskRead }),
                   ChartSeries(id: "w", title: "Write", color: .orange, value: { $0.diskWrite })])
            chart("Network", points, interval, maximum: nil, format: Formatters.rate,
                  [ChartSeries(id: "d", title: "Download", color: .blue, value: { $0.networkDown }),
                   ChartSeries(id: "u", title: "Upload", color: .green, value: { $0.networkUp })])

            HStack {
                Text(verbatim: axisLabel(interval.start)); Spacer(); Text(verbatim: axisLabel(interval.end))
            }
            .font(.caption).foregroundColor(.secondary)
        }
    }

    private func chart(_ title: LocalizedStringKey, _ points: [HistoryPoint], _ interval: DateInterval,
                       maximum: Double?, format: @escaping (Double) -> String,
                       _ series: [ChartSeries]) -> some View {
        HistoryChart(title: title, points: points, interval: interval, series: series,
                     maximum: maximum, format: format, hoverDate: $hoverDate)
    }

    // MARK: - Read-out

    @ViewBuilder
    private func readout(points: [HistoryPoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date = hoverDate,
               let point = HistoryStore.nearest(to: date, in: points, tolerance: range.bucket * 2) {
                Text(verbatim: axisLabel(point.date, full: true)).font(.headline)
                Text(verbatim: [
                    "\(tr("Processor")) \(Formatters.percent(point.cpu))",
                    "\(tr("Memory")) \(Formatters.percent(point.memory))",
                    point.cpuTemperature.map(Formatters.temperature),
                    "\(tr("Disk")) ↓\(Formatters.rate(point.diskRead)) ↑\(Formatters.rate(point.diskWrite))",
                    "\(tr("Network")) ↓\(Formatters.rate(point.networkDown)) ↑\(Formatters.rate(point.networkUp))"
                ].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.callout).monospacedDigit()
                if !point.topProcesses.isEmpty {
                    Text(verbatim: tr("Main apps: %@", point.topProcesses.joined(separator: ", ")))
                        .font(.callout).foregroundColor(.secondary)
                }
            } else {
                Text("Hover over a chart to see values and the busiest apps at that moment.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    private func axisLabel(_ date: Date, full: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = (range == .week || full) ? "E d MMM, HH:mm" : "HH:mm"
        return formatter.string(from: date)
    }
}

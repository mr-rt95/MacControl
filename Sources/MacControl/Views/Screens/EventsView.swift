//
//  EventsView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Journal of "what slowed my Mac down": time, duration, cause, with a chart around each event.
struct EventsView: View {

    let events: [LoggedEvent]
    let store: HistoryStore
    let onClear: () -> Void

    @State private var selectedID: UUID?
    @State private var hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Events from the retention period, newest first.").foregroundColor(.secondary)
                Spacer()
                Button("Clear journal", action: onClear).disabled(events.isEmpty)
            }

            if events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundColor(Palette.good)
                    Text("Nothing has slowed this Mac down recently.")
                }
                .frame(maxWidth: .infinity)
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
            } else {
                ForEach(events) { event in
                    row(event)
                }
            }
        }
    }

    private func row(_ event: LoggedEvent) -> some View {
        let isSelected = selectedID == event.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedID = isSelected ? nil : event.id
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: Self.symbol(event.kind)).foregroundColor(Self.color(event.kind)).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: Self.title(event.kind)).font(.headline)
                        Text(verbatim: timeRange(event)).foregroundColor(.secondary)
                        Text(verbatim: summary(event)).font(.callout)
                        if !event.topProcesses.isEmpty {
                            Text(verbatim: tr("Main apps: %@", event.topProcesses.joined(separator: ", ")))
                                .font(.callout).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected { detail(event) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    /// Chart of the period around the event, taken from the history tiers.
    @ViewBuilder
    private func detail(_ event: LoggedEvent) -> some View {
        let padding: TimeInterval = 600
        let end = (event.end ?? Date()).addingTimeInterval(padding)
        let interval = DateInterval(start: event.start.addingTimeInterval(-padding), end: max(end, event.start.addingTimeInterval(padding)))
        let points = store.points(from: interval.start, to: interval.end)

        if points.count < 2 {
            Text("History for this period is no longer available.").foregroundColor(.secondary)
        } else {
            HistoryChart(title: "Processor", points: points, interval: interval,
                         series: [ChartSeries(id: "cpu", title: "Processor", color: .blue, value: { $0.cpu })],
                         maximum: 1, format: Formatters.percent, hoverDate: $hoverDate, height: 70)
            HistoryChart(title: "Temperature", points: points, interval: interval,
                         series: [ChartSeries(id: "t", title: "Processor", color: .red, value: { $0.cpuTemperature })],
                         maximum: 110, format: Formatters.temperature, hoverDate: $hoverDate, height: 70)
        }
    }

    // MARK: - Text

    private func timeRange(_ event: LoggedEvent) -> String {
        let day = DateFormatter()
        day.dateStyle = .medium
        day.doesRelativeDateFormatting = true
        day.timeStyle = .none
        let time = DateFormatter()
        time.dateFormat = "HH:mm"

        let start = "\(day.string(from: event.start)) \(time.string(from: event.start))"
        guard let end = event.end else { return tr("%@, ongoing", start) }
        return "\(start)–\(time.string(from: end)) (\(FindingPresenter.duration(event.duration())))"
    }

    private func summary(_ event: LoggedEvent) -> String {
        var parts: [String] = []
        switch event.kind {
        case .cpuLoad, .overheating, .throttling:
            parts.append(tr("CPU %@", Formatters.percent(event.peakCPU)))
            if let t = event.peakTemperature { parts.append(Formatters.temperature(t)) }
            if event.kind == .throttling, let limit = event.lowestSpeedLimit {
                parts.append(tr("speed down to %@", "\(limit)%"))
            }
        case .memoryPressure, .swapGrowth:
            if let swap = event.peakSwapBytes { parts.append(tr("swap up to %@", Formatters.bytes(swap))) }
        case .diskAlmostFull:
            if let free = event.lowestFreeFraction { parts.append(tr("%@ free", Formatters.percent(free))) }
        }
        return parts.joined(separator: ", ")
    }

    static func title(_ kind: EventKind) -> String {
        switch kind {
        case .cpuLoad:        return tr("High processor load")
        case .overheating:    return tr("Overheating")
        case .memoryPressure: return tr("Critical memory pressure")
        case .swapGrowth:     return tr("Swap growth")
        case .diskAlmostFull: return tr("Disk almost full")
        case .throttling:     return tr("CPU throttling")
        }
    }

    static func symbol(_ kind: EventKind) -> String {
        switch kind {
        case .cpuLoad:        return "cpu"
        case .overheating:    return "thermometer.high"
        case .memoryPressure, .swapGrowth: return "memorychip"
        case .diskAlmostFull: return "internaldrive"
        case .throttling:     return "tortoise"
        }
    }

    static func color(_ kind: EventKind) -> Color {
        switch kind {
        case .overheating, .memoryPressure, .diskAlmostFull: return Palette.critical
        default: return Palette.warning
        }
    }
}

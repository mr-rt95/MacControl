//
//  MemoryView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Memory breakdown, pressure, swap and the biggest memory consumers.
struct MemoryView: View {

    let snapshot: SystemSnapshot
    let history: MetricHistory

    private var memory: MemoryStats { snapshot.memory }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                MetricCard(title: "Used",
                           value: Formatters.bytes(memory.used),
                           caption: tr("of %@", Formatters.bytes(memory.total))) {
                    Sparkline(values: history.memory.elements, maximum: 1,
                              color: Palette.color(for: memory.pressure))
                        .frame(height: 60)
                }
                MetricCard(title: "Memory pressure", value: "", caption: nil) {
                    HStack(spacing: 8) {
                        Circle().fill(Palette.color(for: memory.pressure)).frame(width: 12, height: 12)
                        Text(memory.pressure.title).font(.title3.weight(.semibold))
                    }
                }
                MetricCard(title: "Swap",
                           value: Formatters.bytes(memory.swapUsed),
                           caption: tr("of %@", Formatters.bytes(memory.swapTotal)),
                           tint: memory.swapUsed > 1_073_741_824 ? Palette.warning : .primary)
            }

            VStack(alignment: .leading, spacing: 10) {
                StackedBar(segments: segments)
                legend
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))

            Text("Top consumers").font(.headline)
            ProcessTable(groups: snapshot.processGroups,
                         initialSort: KeyPathComparator(\ProcessGroup.memoryBytes, order: .reverse))
        }
    }

    // MARK: - Breakdown

    private struct Part: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let bytes: UInt64
        let color: Color
    }

    private var parts: [Part] {
        [
            Part(id: "app", title: "App memory", bytes: memory.app, color: .blue),
            Part(id: "wired", title: "Wired", bytes: memory.wired, color: .orange),
            Part(id: "compressed", title: "Compressed", bytes: memory.compressed, color: .purple),
            Part(id: "cached", title: "Cached files", bytes: memory.cached, color: .teal),
            Part(id: "free", title: "Free", bytes: memory.free, color: .gray.opacity(0.5))
        ]
    }

    private var segments: [StackedBar.Segment] {
        guard memory.total > 0 else { return [] }
        return parts.map { StackedBar.Segment(fraction: Double($0.bytes) / Double(memory.total), color: $0.color) }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], spacing: 6) {
            ForEach(parts) { part in
                HStack(spacing: 6) {
                    Circle().fill(part.color).frame(width: 8, height: 8)
                    Text(part.title).foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    Text(verbatim: Formatters.bytes(part.bytes)).monospacedDigit()
                }
                .font(.callout)
            }
        }
    }
}

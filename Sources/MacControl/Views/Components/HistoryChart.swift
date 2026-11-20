//
//  HistoryChart.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// A line series of a history chart.
struct ChartSeries: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let color: Color
    let value: (HistoryPoint) -> Double?
}

/// Time-based line chart drawn with `Canvas`, with a hover cursor shared between charts.
struct HistoryChart: View {

    let title: LocalizedStringKey
    let points: [HistoryPoint]
    let interval: DateInterval
    let series: [ChartSeries]
    /// Fixed upper bound of the Y axis; `nil` scales to the data.
    var maximum: Double?
    let format: (Double) -> String
    @Binding var hoverDate: Date?
    var height: CGFloat = 90

    /// Points further apart than this are not connected (the app was not running).
    private var gapLimit: TimeInterval {
        let sorted = zip(points, points.dropFirst()).map { $1.time - $0.time }
        let typical = sorted.sorted()[safe: sorted.count / 2] ?? 60
        return max(typical * 3, 15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                ForEach(series) { item in
                    HStack(spacing: 4) {
                        Circle().fill(item.color).frame(width: 7, height: 7)
                        Text(item.title).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            GeometryReader { proxy in
                ZStack {
                    Canvas { context, size in draw(in: &context, size: size) }
                    HoverTracker { location in
                        guard let location = location, interval.duration > 0, proxy.size.width > 0 else {
                            hoverDate = nil
                            return
                        }
                        let fraction = Double(location.x / proxy.size.width)
                        hoverDate = interval.start.addingTimeInterval(fraction * interval.duration)
                    }
                }
            }
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.track.opacity(0.5)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard interval.duration > 0, size.width > 0 else { return }

        let all = series.flatMap { item in points.compactMap(item.value) }
        let top = max(maximum ?? (all.max() ?? 1) * 1.1, 0.000_001)

        func position(_ time: TimeInterval, _ value: Double) -> CGPoint {
            CGPoint(x: CGFloat((time - interval.start.timeIntervalSince1970) / interval.duration) * size.width,
                    y: size.height - CGFloat(min(max(value / top, 0), 1)) * (size.height - 2) - 1)
        }

        for item in series {
            var path = Path()
            var previousTime: TimeInterval?
            for point in points {
                guard let value = item.value(point) else { previousTime = nil; continue }
                let location = position(point.time, value)
                if let previous = previousTime, point.time - previous <= gapLimit {
                    path.addLine(to: location)
                } else {
                    path.move(to: location)
                }
                previousTime = point.time
            }
            context.stroke(path, with: .color(item.color), lineWidth: 1.4)
        }

        if let hover = hoverDate, hover >= interval.start, hover <= interval.end {
            let x = CGFloat(hover.timeIntervalSince(interval.start) / interval.duration) * size.width
            var cursor = Path()
            cursor.move(to: CGPoint(x: x, y: 0))
            cursor.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(cursor, with: .color(.primary.opacity(0.5)), lineWidth: 1)
        }

        // Axis maximum, top-left.
        context.draw(Text(format(top)).font(.system(size: 9)).foregroundColor(.secondary),
                     at: CGPoint(x: 4, y: 8), anchor: .leading)
    }
}

extension Array {
    /// Element at `index`, or `nil` when out of range.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

//
//  Sparkline.swift
//  MacControl
//

import SwiftUI

/// A small filled line chart drawn with `Canvas` (the Charts framework needs macOS 13).
struct Sparkline: View {

    let values: [Double]
    /// Upper bound of the Y axis. `nil` scales to the largest value seen.
    var maximum: Double?
    var color: Color = .accentColor
    /// Number of samples that fill the full width; shorter series grow in from the right.
    var capacity = 120

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, size.width > 0, size.height > 0 else { return }

            let top = max(maximum ?? values.max() ?? 1, 0.000_001)
            let step = size.width / CGFloat(max(capacity - 1, 1))
            let firstX = size.width - CGFloat(values.count - 1) * step

            var line = Path()
            for (index, value) in values.enumerated() {
                let x = firstX + CGFloat(index) * step
                let y = size.height - CGFloat(min(max(value / top, 0), 1)) * size.height
                if index == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: firstX, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .color(color.opacity(0.18)))
            context.stroke(line, with: .color(color), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

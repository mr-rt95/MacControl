//
//  BarViews.swift
//  MacControl
//

import SwiftUI

/// A horizontal progress bar.
struct ProgressBar: View {

    /// Fill level, `0...1`.
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Formatters.percent(fraction))
    }
}

/// A bar split into colored segments, e.g. the memory breakdown.
struct StackedBar: View {

    struct Segment: Identifiable {
        let id = UUID()
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, proxy.size.width * CGFloat(segment.fraction)))
                }
                Spacer(minLength: 0)
            }
            .background(Palette.track)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

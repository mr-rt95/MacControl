//
//  MetricCard.swift
//  MacControl
//

import SwiftUI

/// A titled card with a large value, an optional caption and free-form content below.
struct MetricCard<Content: View>: View {

    let title: LocalizedStringKey
    let value: String
    var caption: String?
    var tint: Color = .primary
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(verbatim: value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tint)
            if let caption = caption {
                Text(verbatim: caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }
}

extension MetricCard where Content == EmptyView {
    init(title: LocalizedStringKey, value: String, caption: String? = nil, tint: Color = .primary) {
        self.init(title: title, value: value, caption: caption, tint: tint) { EmptyView() }
    }
}

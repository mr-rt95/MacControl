//
//  FindingCard.swift
//  MacControl
//

import SwiftUI
import MacControlCore

extension Severity {
    var color: Color {
        switch self {
        case .info:     return .blue
        case .warning:  return Palette.warning
        case .serious, .critical: return Palette.critical
        }
    }

    var symbol: String {
        switch self {
        case .info:     return "info.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .serious:  return "exclamationmark.octagon.fill"
        case .critical: return "flame.fill"
        }
    }
}

/// One diagnostic finding: cause, advice, a button to the related screen and the underlying data.
struct FindingCard: View {

    let finding: Finding
    var prominent = false
    let navigate: (Screen) -> Void

    @State private var showsData = false

    var body: some View {
        let text = FindingPresenter.text(for: finding)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: finding.severity.symbol)
                    .font(.system(size: prominent ? 30 : 20))
                    .foregroundColor(finding.severity.color)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: text.title)
                        .font(prominent ? .title2.weight(.semibold) : .headline)
                    Text(verbatim: text.detail)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: text.advice)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Button(FindingPresenter.buttonTitle(for: finding)) {
                    navigate(FindingPresenter.screen(for: finding))
                }
                Button(showsData ? "Hide data" : "Show data") { showsData.toggle() }
                    .buttonStyle(.link)
            }

            if showsData {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(finding.evidence) { item in
                        HStack {
                            Text(verbatim: tr(item.label)).foregroundColor(.secondary)
                            Spacer()
                            Text(verbatim: tr(item.value)).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.track))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(finding.severity.color.opacity(0.5), lineWidth: prominent ? 2 : 1))
        )
    }
}

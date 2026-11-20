//
//  DiagnosisView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Main screen: either "everything is fine" or the cause of the slowdown and what to do about it.
struct DiagnosisView: View {

    let snapshot: SystemSnapshot
    let analysis: AnalysisResult
    let navigate: (Screen) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let headline = analysis.findings.first {
                FindingCard(finding: headline, prominent: true, navigate: navigate)
                if analysis.findings.count > 1 {
                    Text("Other findings").font(.headline)
                    ForEach(analysis.findings.dropFirst()) { finding in
                        FindingCard(finding: finding, navigate: navigate)
                    }
                }
            } else {
                allClear
            }

            Text("These are heuristics, not an absolute diagnosis. Each conclusion shows the data it is based on.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var allClear: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(Palette.good)
            VStack(alignment: .leading, spacing: 6) {
                Text("Everything is fine").font(.title2.weight(.semibold))
                Text("No performance problems detected right now.").foregroundColor(.secondary)
                Text(verbatim: summary).font(.callout).monospacedDigit().foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    private var summary: String {
        var parts = [
            "\(tr("Processor")) \(Formatters.percent(snapshot.cpu.total))",
            "\(tr("Memory")) \(Formatters.percent(snapshot.memory.usedFraction))"
        ]
        if let temperature = snapshot.cpuTemperature { parts.append(Formatters.temperature(temperature)) }
        return parts.joined(separator: " · ")
    }
}

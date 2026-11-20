//
//  SpeedUpView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Optional tweaks for older Macs. Nothing is applied automatically, and each change can be undone.
struct SpeedUpView: View {

    @ObservedObject var model: TuningViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("These settings reduce visual effects. They are suggestions: nothing changes until you press Apply, and the original value is saved so you can restore it.")
                .foregroundColor(.secondary)

            ForEach(TuningRecommendation.all) { rec in
                card(rec)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Other ideas").font(.headline)
                Text(spotlightText)
                Text("Review widgets and cloud-sync apps (iCloud Drive, Dropbox, OneDrive) in Startup & services: each one costs memory and CPU in the background.")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
        }
        .banner($model.banner)
        .onAppear { model.refresh() }
    }

    private var spotlightText: String {
        switch model.spotlightEnabled {
        case true?:  return tr("Spotlight indexing is on. If the Mac is busy with 'mds' or 'mdworker' for hours, rebuilding the index in System Settings ▸ Siri & Spotlight can help. MacControl does not change it.")
        case false?: return tr("Spotlight indexing is off.")
        default:     return tr("Spotlight status is unknown.")
        }
    }

    private func card(_ rec: TuningRecommendation) -> some View {
        let isApplied = model.applied.contains(rec.id)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: tr(rec.title)).font(.headline)
                    Text(rec.risk == .low ? "Risk: low" : "Risk: medium")
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.good.opacity(0.18)))
                }
                Text(verbatim: tr(rec.effect)).foregroundColor(.secondary)
            }
            Spacer()
            if model.busy == rec.id {
                ProgressView().controlSize(.small)
            } else if isApplied && model.restorable.contains(rec.id) {
                Button("Restore as it was") { model.restore(rec) }
            } else if isApplied {
                Label("Already on", systemImage: "checkmark").foregroundColor(Palette.good)
            } else {
                Button(rec.requiresSystemSettings ? "Turn on in System Settings" : "Apply") { model.apply(rec) }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }
}

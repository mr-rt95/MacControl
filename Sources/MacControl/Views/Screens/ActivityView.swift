//
//  ActivityView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Log of everything MacControl moved to the Trash, with Undo.
struct ActivityView: View {

    @ObservedObject var management: ManagementModel
    @State private var banner: Banner?

    var body: some View {
        // Reading `logRevision` makes the list refresh after every operation.
        let _ = management.logRevision
        let records = management.trasher.log.records

        VStack(alignment: .leading, spacing: 12) {
            Text("Everything MacControl removed is listed here. Items stay in the Trash until you empty it.")
                .foregroundColor(.secondary)

            if records.isEmpty {
                Text("No actions yet.").foregroundColor(.secondary)
            }
            ForEach(records) { record in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: record.title).font(.headline)
                        Text(verbatim: "\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(tr("%@ items", "\(record.items.count)")) · \(Formatters.bytes(record.totalBytes))")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(record.items.prefix(3), id: \.originalPath) { item in
                            Text(verbatim: item.originalPath).font(.caption2).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        if record.items.count > 3 {
                            Text(verbatim: tr("…and %@ more", "\(record.items.count - 3)")).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if record.canUndo {
                        Button("Undo") {
                            management.undo(recordID: record.id) { banner = $0 }
                        }
                    } else {
                        Text("Restored").font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
            }
        }
        .banner($banner)
    }
}

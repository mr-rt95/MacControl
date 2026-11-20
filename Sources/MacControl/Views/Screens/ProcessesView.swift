//
//  ProcessesView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Applications and their load, with a safe "Quit" action.
struct ProcessesView: View {

    let groups: [ProcessGroup]
    @ObservedObject var model: ProcessesViewModel

    @State private var selectedID: String?
    @State private var sortOrder = [KeyPathComparator(\ProcessGroup.cpuPercent, order: .reverse)]

    private var rows: [ProcessGroup] { Array(groups.sorted(using: sortOrder).prefix(80)) }
    private var selected: ProcessGroup? { groups.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select an app and press Quit. Apps are asked to close normally first.")
                    .foregroundColor(.secondary)
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button("Quit app") { if let group = selected { model.requestQuit(group) } }
                    .disabled(selected == nil || model.isWorking)
            }
            if let group = selected, !model.canQuit(group) {
                Label(ProcessesViewModel.explanation(for: model.verdict(for: group), name: group.name),
                      systemImage: "lock.fill")
                    .foregroundColor(.secondary)
            }

            Table(rows, selection: $selectedID, sortOrder: $sortOrder) {
                TableColumn("Process", value: \.name) { group in
                    HStack(spacing: 6) {
                        if !model.canQuit(group) {
                            Image(systemName: "lock.fill").foregroundColor(.secondary).font(.caption)
                        }
                        Text(verbatim: group.name).lineLimit(1)
                    }
                }
                TableColumn("CPU", value: \.cpuPercent) { Text(verbatim: Formatters.cpuPercent($0.cpuPercent)).monospacedDigit() }
                    .width(min: 60, ideal: 70, max: 90)
                TableColumn("Memory", value: \.memoryBytes) { Text(verbatim: Formatters.bytes($0.memoryBytes)).monospacedDigit() }
                    .width(min: 70, ideal: 90, max: 120)
                TableColumn("Disk", value: \.diskBytesPerSecond) { Text(verbatim: Formatters.rate($0.diskBytesPerSecond)).monospacedDigit() }
                    .width(min: 80, ideal: 100, max: 140)
            }
            .frame(minHeight: 380)

            Text("Processes owned by the system are locked. Other users' processes can be quit only with the administrator helper.")
                .font(.caption).foregroundColor(.secondary)
        }
        .banner($model.banner)
        .confirmation($model.preview)
        .alert(item: $model.forceRequest) { request in
            Alert(
                title: Text(verbatim: tr("%@ did not respond", request.name)),
                message: Text("Force quitting ends it immediately. Unsaved changes will be lost."),
                primaryButton: .destructive(Text("Force Quit")) { model.forceQuit(request) },
                secondaryButton: .cancel()
            )
        }
    }
}

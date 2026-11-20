//
//  ProcessTable.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Sortable list of applications and their resource usage.
/// Helper processes are already merged into their parent app by `ProcessGroup`.
struct ProcessTable: View {

    private static let maximumRows = 60

    let groups: [ProcessGroup]
    @State private var sortOrder: [KeyPathComparator<ProcessGroup>]

    init(groups: [ProcessGroup], initialSort: KeyPathComparator<ProcessGroup>) {
        self.groups = groups
        _sortOrder = State(initialValue: [initialSort])
    }

    private var rows: [ProcessGroup] {
        Array(groups.sorted(using: sortOrder).prefix(Self.maximumRows))
    }

    var body: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Process", value: \.name) { group in
                Text(verbatim: group.name).lineLimit(1)
            }
            TableColumn("Procs", value: \.processCount) { group in
                Text(verbatim: "\(group.processCount)").monospacedDigit().foregroundColor(.secondary)
            }
            .width(min: 40, ideal: 50, max: 70)
            TableColumn("CPU", value: \.cpuPercent) { group in
                Text(verbatim: Formatters.cpuPercent(group.cpuPercent)).monospacedDigit()
            }
            .width(min: 60, ideal: 70, max: 90)
            TableColumn("Memory", value: \.memoryBytes) { group in
                Text(verbatim: Formatters.bytes(group.memoryBytes)).monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn("Disk", value: \.diskBytesPerSecond) { group in
                Text(verbatim: Formatters.rate(group.diskBytesPerSecond)).monospacedDigit()
            }
            .width(min: 80, ideal: 100, max: 140)
        }
        .frame(minHeight: 300)
    }
}

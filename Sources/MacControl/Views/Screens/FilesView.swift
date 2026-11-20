//
//  FilesView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Biggest files, files not opened for a year, and duplicates. Everything is chosen by hand.
struct FilesView: View {

    @ObservedObject var model: FilesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $model.mode) {
                Text("Largest files").tag(FilesViewModel.Mode.large)
                Text("Not opened for a year").tag(FilesViewModel.Mode.old)
                Text("Duplicates").tag(FilesViewModel.Mode.duplicates)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)

            HStack {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning in the background… this can take a few minutes.").foregroundColor(.secondary)
                    Button("Stop") { model.cancelScan() }
                } else {
                    Button(model.scanned.contains(model.mode) ? "Scan again" : "Scan") { model.scan() }
                }
                Spacer()
                Text(verbatim: tr("Selected: %@", Formatters.bytes(model.selectedBytes))).monospacedDigit()
                Button("Review and remove…") { model.requestRemoval() }.disabled(model.selection.isEmpty)
            }

            Text("Personal folders are never cleaned automatically. Only the files you tick here are moved to the Trash.")
                .font(.caption).foregroundColor(.secondary)

            switch model.mode {
            case .large:      fileList(model.largeFiles)
            case .old:        fileList(model.oldFiles)
            case .duplicates: duplicateList
            }
        }
        .banner($model.banner, onUndo: { model.undo($0) })
        .confirmation($model.preview)
    }

    @ViewBuilder
    private func fileList(_ files: [FoundFile]) -> some View {
        if files.isEmpty {
            Text(model.scanned.contains(model.mode) ? "Nothing found." : "Press Scan to look for files.")
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(files) { file in
                    Toggle(isOn: Binding(get: { model.selection.contains(file.url) }, set: { _ in model.toggle(file.url) })) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Text(verbatim: file.url.deletingLastPathComponent().path).font(.caption)
                                    .foregroundColor(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            if let date = file.lastAccessed {
                                Text(date, style: .date).font(.caption).foregroundColor(.secondary)
                            }
                            Text(verbatim: Formatters.bytes(file.bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    Divider()
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
        }
    }

    @ViewBuilder
    private var duplicateList: some View {
        if model.duplicates.isEmpty {
            Text(model.scanned.contains(.duplicates) ? "No duplicates found." : "Press Scan to look in Downloads, Documents, Desktop, Pictures, Movies and Music.")
                .foregroundColor(.secondary)
        } else {
            ForEach(model.duplicates) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: tr("%@ copies · %@ each · %@ can be freed", "\(group.files.count)", Formatters.bytes(group.bytes), Formatters.bytes(group.wastedBytes)))
                        .font(.headline)
                    ForEach(group.files, id: \.self) { url in
                        Toggle(isOn: Binding(get: { model.selection.contains(url) }, set: { _ in model.toggleDuplicate(url, in: group) })) {
                            Text(verbatim: url.path).lineLimit(1).truncationMode(.middle)
                        }
                        .toggleStyle(.checkbox)
                    }
                    Text("At least one copy always stays.").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
            }
        }
    }
}

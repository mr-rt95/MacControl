//
//  DiskView.swift
//  MacControl
//

import SwiftUI
import AppKit
import MacControlCore

/// Startup-volume capacity, read/write throughput and the most active apps.
struct DiskView: View {

    let snapshot: SystemSnapshot
    let history: MetricHistory
    @ObservedObject var folders: FolderUsageViewModel

    private var disk: DiskStats { snapshot.disk }

    // MARK: - What takes space

    private var folderBrowser: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What takes space").font(.headline)
                Spacer()
                if folders.isScanning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { folders.cancel() }
                } else {
                    Button(folders.hasScanned ? "Scan again" : "Scan home folder") { folders.scan() }
                }
            }
            if folders.hasScanned {
                HStack(spacing: 8) {
                    Button { folders.goUp() } label: { Image(systemName: "chevron.up") }.disabled(!folders.canGoUp)
                    Text(verbatim: folders.folder.path).font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.head)
                    Spacer()
                    Text(verbatim: Formatters.bytes(folders.totalBytes)).font(.caption).monospacedDigit()
                }
                ForEach(folders.entries.prefix(40)) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.isDirectory ? "folder" : "doc").foregroundColor(.secondary).frame(width: 18)
                        Button(entry.name) { folders.open(entry) }
                            .buttonStyle(.plain).disabled(!entry.isDirectory)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        ProgressBar(fraction: folders.totalBytes == 0 ? 0 : Double(entry.bytes) / Double(folders.totalBytes),
                                    color: .accentColor, height: 5).frame(width: 120)
                        Text(verbatim: Formatters.bytes(entry.bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.plain).help(tr("Show in Finder"))
                    }
                    .font(.callout)
                }
                Text("Read-only: nothing is removed here. Use Cleanup or Large files to free space.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("Scans your home folder and lets you open folders to find what is using the space. It can take a minute.")
                    .font(.callout).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Startup volume").font(.headline)
                    Spacer()
                    Text(verbatim: tr("%@ free of %@", Formatters.bytes(disk.availableBytes), Formatters.bytes(disk.totalBytes)))
                        .foregroundColor(.secondary)
                }
                ProgressBar(fraction: disk.usedFraction, color: Palette.color(forLoad: disk.usedFraction), height: 14)
                if disk.totalBytes > 0 && disk.freeFraction < 0.15 {
                    Label("Low free space slows down an older Mac.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundColor(Palette.warning)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))

            HStack(alignment: .top, spacing: 14) {
                MetricCard(title: "Read", value: Formatters.rate(disk.readBytesPerSecond)) {
                    Sparkline(values: history.diskRead.elements, color: .blue).frame(height: 50)
                }
                MetricCard(title: "Write", value: Formatters.rate(disk.writeBytesPerSecond)) {
                    Sparkline(values: history.diskWrite.elements, color: .orange).frame(height: 50)
                }
            }

            folderBrowser

            Text("Most active apps").font(.headline)
            ProcessTable(groups: snapshot.processGroups,
                         initialSort: KeyPathComparator(\ProcessGroup.diskBytesPerSecond, order: .reverse))
        }
    }
}

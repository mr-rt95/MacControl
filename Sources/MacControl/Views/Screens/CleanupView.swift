//
//  CleanupView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Finds removable files in known-safe locations; the user ticks what to move to the Trash.
struct CleanupView: View {

    @ObservedObject var model: CleanupViewModel
    @State private var showEmptyTrashAlert = false
    @State private var expanded: Set<CleanupCategory> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ForEach(CleanupViewModel.selectableCategories) { category in
                categoryCard(category)
            }
            trashCard
            snapshotsCard
        }
        .banner($model.banner, onUndo: { model.undo($0) })
        .confirmation($model.preview)
        .onAppear { if model.results.isEmpty { model.scan() } }
        .alert("Empty the Trash?", isPresented: $showEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty in Finder…", role: .destructive) { model.emptyTrashViaFinder() }
        } message: {
            Text("This permanently deletes everything in the Trash. Finder will ask you to confirm.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Scanning…").foregroundColor(.secondary)
                Button("Stop") { model.cancelScan() }
            } else {
                Button("Scan again") { model.scan() }
            }
            Spacer()
            Text(verbatim: tr("Selected: %@", Formatters.bytes(model.selectedBytes))).monospacedDigit()
            Button("Review and clean…") { model.requestCleanup() }
                .disabled(model.selection.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Categories

    private func categoryCard(_ category: CleanupCategory) -> some View {
        let result = model.results[category]
        let items = result?.items ?? []
        let isOpen = expanded.contains(category)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isOpen { expanded.remove(category) } else { expanded.insert(category) }
            } label: {
                HStack {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(category)).font(.headline)
                        Text(Self.explanation(category)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if result == nil { ProgressView().controlSize(.small) }
                    else if result?.accessDenied == true { Text("Needs Full Disk Access").font(.caption).foregroundColor(Palette.warning) }
                    else { Text(verbatim: Formatters.bytes(result?.totalBytes ?? 0)).monospacedDigit() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                if items.isEmpty {
                    Text("Nothing to clean here.").foregroundColor(.secondary).font(.callout)
                } else {
                    HStack {
                        if items.contains(where: { $0.risk == .safe }) {
                            Button("Select all") { model.selectAllSafe(in: category) }
                        }
                        Button("Clear selection") { model.deselectAll(in: category) }
                    }
                    ForEach(items.prefix(100)) { item in
                        itemRow(item)
                    }
                    if items.count > 100 {
                        Text(verbatim: tr("…and %@ more", "\(items.count - 100)")).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    private func itemRow(_ item: CleanupItem) -> some View {
        Toggle(isOn: Binding(get: { model.selection.contains(item.url) }, set: { _ in model.toggle(item) })) {
            HStack {
                Text(verbatim: item.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let date = item.modified {
                    Text(date, style: .date).font(.caption).foregroundColor(.secondary)
                }
                Text(verbatim: Formatters.bytes(item.bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Trash and snapshots

    private var trashCard: some View {
        let result = model.results[.trash]
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trash").font(.headline)
                if result?.accessDenied == true {
                    Text("Grant Full Disk Access to MacControl to see its size.").font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Emptying deletes files permanently, so it is done through Finder.").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if result?.accessDenied != true { Text(verbatim: Formatters.bytes(result?.totalBytes ?? 0)).monospacedDigit() }
            Button("Empty Trash…") { showEmptyTrashAlert = true }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    private var snapshotsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time Machine local snapshots").font(.headline)
            if model.snapshots.isEmpty {
                Text("No local snapshots.").foregroundColor(.secondary).font(.callout)
            } else {
                Text(verbatim: tr("%@ snapshots found. Removing them needs the administrator helper (see Permissions).", "\(model.snapshots.count)"))
                    .font(.callout).foregroundColor(.secondary)
                ForEach(model.snapshots) { snapshot in
                    HStack {
                        Text(verbatim: snapshot.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? snapshot.name).font(.caption)
                        Spacer()
                        if model.canDeleteSnapshots { Button("Delete…") { model.requestDeleteSnapshot(snapshot) } }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    // MARK: - Text

    static func title(_ category: CleanupCategory) -> LocalizedStringKey {
        switch category {
        case .userCaches:      return "App caches"
        case .logs:            return "Logs"
        case .trash:           return "Trash"
        case .oldDownloads:    return "Old downloads"
        case .temporaryFiles:  return "Temporary files"
        case .developerCaches: return "Developer caches"
        case .iosBackups:      return "iPhone and iPad backups"
        }
    }

    static func explanation(_ category: CleanupCategory) -> LocalizedStringKey {
        switch category {
        case .userCaches:      return "Rebuilt automatically. Apps may start a little slower the first time."
        case .logs:            return "Diagnostic logs written by apps."
        case .trash:           return "Items you already deleted."
        case .oldDownloads:    return "Files in Downloads not touched for 90 days. Choose carefully."
        case .temporaryFiles:  return "Files in the temporary folder older than three days."
        case .developerCaches: return "Xcode DerivedData, device support, npm and Gradle caches. Rebuilt on demand."
        case .iosBackups:      return "May be the only copy of your phone's data. Removed only after explicit confirmation."
        }
    }
}

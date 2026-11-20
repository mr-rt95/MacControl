//
//  CleanupViewModel.swift
//  MacControl
//

import Foundation
import AppKit
import MacControlCore

/// Drives the Cleanup screen: scanning, selection, preview and execution.
final class CleanupViewModel: ObservableObject {

    /// Categories whose items can be selected for the Trash. The Trash itself is emptied through Finder.
    static let selectableCategories: [CleanupCategory] = [.userCaches, .logs, .temporaryFiles, .developerCaches, .oldDownloads, .iosBackups]

    @Published private(set) var results: [CleanupCategory: CleanupCategoryResult] = [:]
    @Published private(set) var snapshots: [TimeMachineSnapshot] = []
    @Published private(set) var isScanning = false
    @Published var selection = Set<URL>()
    @Published var preview: ActionPreview?
    @Published var banner: Banner?

    private unowned let model: ManagementModel
    private let scanner = CleanupScanner()
    private var token = CancellationToken()

    init(model: ManagementModel) {
        self.model = model
    }

    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    var selectedItems: [CleanupItem] {
        Self.selectableCategories.flatMap { results[$0]?.items ?? [] }.filter { selection.contains($0.url) }
    }

    // MARK: - Scanning

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        results = [:]
        selection = []
        token = CancellationToken()
        let token = self.token

        DispatchQueue.global(qos: .utility).async { [scanner] in
            for category in CleanupCategory.allCases {
                if token.isCancelled { break }
                let result = scanner.scan(category, isCancelled: { token.isCancelled })
                DispatchQueue.main.async { self.results[category] = result }
            }
            let snapshots = TimeMachineSnapshots.list()
            DispatchQueue.main.async {
                self.snapshots = snapshots
                self.isScanning = false
            }
        }
    }

    func cancelScan() { token.cancel() }

    // MARK: - Selection

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    /// Selects every item of a category that is safe to remove in bulk.
    /// Personal and irreplaceable items are never bulk-selected.
    func selectAllSafe(in category: CleanupCategory) {
        for item in results[category]?.items ?? [] where item.risk == .safe { selection.insert(item.url) }
    }

    func deselectAll(in category: CleanupCategory) {
        for item in results[category]?.items ?? [] { selection.remove(item.url) }
    }

    // MARK: - Preview and execution

    func requestCleanup() {
        let items = selectedItems
        guard !items.isEmpty else { return }

        var warnings: [String] = []
        var acknowledgement: String?
        if items.contains(where: { $0.risk == .personal }) {
            warnings.append(tr("Includes files from your Downloads folder that you may still need."))
        }
        if items.contains(where: { $0.risk == .irreplaceable }) {
            warnings.append(tr("Includes iPhone/iPad backups. If this is the only backup, the device data cannot be recovered after the Trash is emptied."))
            acknowledgement = tr("I understand that this may be the only copy of my device data.")
        }

        preview = ActionPreview(
            title: tr("Move to the Trash?"),
            message: tr("Nothing is deleted permanently. You can restore these items from the Trash or with Undo in Activity."),
            items: items.map { PreviewItem(path: $0.url.path, bytes: $0.bytes) },
            warnings: warnings, acknowledgement: acknowledgement,
            confirmTitle: tr("Move to the Trash"),
            perform: { [weak self] in self?.executeCleanup(items) }
        )
    }

    private func executeCleanup(_ items: [CleanupItem]) {
        let requests = items.map { TrashRequest(url: $0.url, bytes: $0.bytes) }
        model.moveToTrash(requests, kind: .cleanup, title: tr("Cleanup")) { [weak self] report, banner in
            guard let self = self else { return }
            let done = Set(report.trashed.map(\.originalPath))
            for category in CleanupCategory.allCases {
                guard let result = self.results[category] else { continue }
                self.results[category] = CleanupCategoryResult(category: category,
                                                               items: result.items.filter { !done.contains($0.url.path) },
                                                               accessDenied: result.accessDenied)
            }
            self.selection = self.selection.filter { !done.contains($0.path) }
            self.banner = banner
        }
    }

    // MARK: - Time Machine snapshots (administrator helper)

    var canDeleteSnapshots: Bool { model.helper.isUsable }

    func requestDeleteSnapshot(_ snapshot: TimeMachineSnapshot) {
        preview = ActionPreview(
            title: tr("Delete this snapshot?"),
            message: tr("Local Time Machine snapshots are deleted permanently and cannot be restored. Your backups on the Time Machine disk are not affected."),
            items: [PreviewItem(path: snapshot.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? snapshot.name, bytes: 0)],
            confirmTitle: tr("Delete snapshot"),
            perform: { [weak self] in self?.deleteSnapshot(snapshot) }
        )
    }

    private func deleteSnapshot(_ snapshot: TimeMachineSnapshot) {
        guard let client = model.helper.commandClient() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let failure = client.deleteSnapshot(snapshot.name)
            let snapshots = TimeMachineSnapshots.list()
            DispatchQueue.main.async {
                self.snapshots = snapshots
                self.banner = failure == nil
                    ? Banner(message: tr("Snapshot deleted."))
                    : Banner(message: tr("The snapshot could not be deleted."), isError: true)
            }
        }
    }

    // MARK: - Trash

    /// Empties the Trash through Finder, which shows its own confirmation. This is the one place where
    /// files end up deleted for good, so it is never part of a bulk cleanup.
    func emptyTrashViaFinder() {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty the trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        banner = error == nil ? nil : Banner(message: tr("Finder could not empty the Trash. Allow MacControl to control Finder in System Settings ▸ Privacy & Security ▸ Automation."), isError: true)
    }

    func undo(_ id: UUID) {
        model.undo(recordID: id) { [weak self] banner in self?.banner = banner }
    }
}

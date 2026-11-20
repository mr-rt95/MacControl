//
//  ManagementModel.swift
//  MacControl
//

import Foundation
import MacControlCore

/// Owns the shared safety services and the view models of the management screens,
/// so scan results survive switching between sidebar items.
final class ManagementModel: ObservableObject {

    let trasher: SafeTrasher
    let helper: HelperManager
    /// Incremented whenever the action log changes, so the Activity screen refreshes.
    @Published private(set) var logRevision = 0

    private(set) lazy var cleanup = CleanupViewModel(model: self)
    private(set) lazy var processes = ProcessesViewModel(model: self)
    private(set) lazy var apps = AppsViewModel(model: self)
    private(set) lazy var startup = StartupViewModel(model: self)
    private(set) lazy var tuning = TuningViewModel(model: self)
    private(set) lazy var files = FilesViewModel(model: self)
    private(set) lazy var modes = ModesViewModel()
    private(set) lazy var folders = FolderUsageViewModel()
    private(set) lazy var report = ReportViewModel()

    init(trasher: SafeTrasher = SafeTrasher(), helper: HelperManager) {
        self.trasher = trasher
        self.helper = helper
    }

    /// Moves items to the Trash off the main thread and reports the outcome as a banner.
    func moveToTrash(_ requests: [TrashRequest], kind: ActionKind, title: String,
                     completion: @escaping (TrashReport, Banner) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [trasher] in
            let report = trasher.execute(requests, kind: kind, title: title)
            DispatchQueue.main.async {
                self.logRevision += 1
                completion(report, Self.banner(for: report))
            }
        }
    }

    /// Notes that something outside `moveToTrash` wrote to the action log.
    func bumpLog() { logRevision += 1 }

    /// Restores a logged operation from the Trash.
    func undo(recordID: UUID, completion: @escaping (Banner) -> Void) {
        let client = helper.commandClient()
        DispatchQueue.global(qos: .userInitiated).async { [trasher] in
            let report = trasher.undo(recordID: recordID)
            var restored = report.restored, failed = report.failed

            // Items the helper moved into its quarantine are restored through the helper.
            for item in trasher.log.record(id: recordID)?.items ?? [] where !item.isRestored {
                guard let quarantineID = item.quarantineID else { continue }
                if let client = client, client.restoreQuarantined(quarantineID) == nil {
                    trasher.log.markRestored(recordID: recordID, originalPaths: [item.originalPath])
                    restored += 1
                } else {
                    failed += 1
                }
            }
            DispatchQueue.main.async {
                self.logRevision += 1
                var message = tr("Restored %@ items.", "\(restored)")
                if failed > 0 { message += " " + tr("%@ could not be restored (already emptied from the Trash or the spot is taken).", "\(failed)") }
                completion(Banner(message: message, isError: restored == 0 && failed > 0))
            }
        }
    }

    static func banner(for report: TrashReport) -> Banner {
        var parts: [String] = []
        if !report.trashed.isEmpty {
            parts.append(tr("Moved %@ items (%@) to the Trash.", "\(report.trashed.count)", Formatters.bytes(report.trashedBytes)))
        }
        if !report.failures.isEmpty {
            parts.append(tr("%@ items were skipped (protected, missing or in use).", "\(report.failures.count)"))
        }
        return Banner(message: parts.joined(separator: " "), isError: report.trashed.isEmpty,
                      undoRecordID: report.recordID)
    }
}

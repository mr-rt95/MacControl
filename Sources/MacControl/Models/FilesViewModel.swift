//
//  FilesViewModel.swift
//  MacControl
//

import Foundation
import MacControlCore

/// Drives the "Large files & duplicates" screen. Results in personal folders are only ever removed
/// when the user ticks that exact file.
final class FilesViewModel: ObservableObject {

    enum Mode: String, CaseIterable { case large, old, duplicates }

    @Published var mode = Mode.large
    @Published private(set) var largeFiles: [FoundFile] = []
    @Published private(set) var oldFiles: [FoundFile] = []
    @Published private(set) var duplicates: [DuplicateGroup] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanned: Set<Mode> = []
    @Published var selection = Set<URL>()
    @Published var preview: ActionPreview?
    @Published var banner: Banner?

    static let largeThreshold: UInt64 = 100 * 1_048_576
    static let oldThreshold: UInt64 = 20 * 1_048_576
    static let oldAge: TimeInterval = 365 * 86_400

    private unowned let model: ManagementModel
    private var token = CancellationToken()
    private let protection = ProtectedPaths()

    init(model: ManagementModel) {
        self.model = model
    }

    // MARK: - Scanning

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        selection = []
        token = CancellationToken()
        let token = self.token
        let mode = self.mode
        let home = FileManager.default.homeDirectoryForCurrentUser

        DispatchQueue.global(qos: .background).async {
            switch mode {
            case .large:
                let files = LargeFileFinder().find(minimumBytes: Self.largeThreshold, isCancelled: { token.isCancelled })
                DispatchQueue.main.async { self.largeFiles = files }
            case .old:
                let cutoff = Date().addingTimeInterval(-Self.oldAge)
                let files = LargeFileFinder().find(minimumBytes: Self.oldThreshold, notOpenedSince: cutoff, isCancelled: { token.isCancelled })
                DispatchQueue.main.async { self.oldFiles = files }
            case .duplicates:
                let roots = ["Downloads", "Documents", "Desktop", "Pictures", "Movies", "Music"].map { home.appendingPathComponent($0) }
                let groups = DuplicateFinder(roots: roots).find(isCancelled: { token.isCancelled })
                DispatchQueue.main.async { self.duplicates = groups }
            }
            DispatchQueue.main.async {
                self.isScanning = false
                if !token.isCancelled { self.scanned.insert(mode) }
            }
        }
    }

    func cancelScan() { token.cancel() }

    // MARK: - Selection

    func toggle(_ url: URL) {
        if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
    }

    /// Ticks a duplicate, but never the last remaining copy of a group.
    func toggleDuplicate(_ url: URL, in group: DuplicateGroup) {
        if selection.contains(url) {
            selection.remove(url)
        } else if group.files.filter({ selection.contains($0) }).count < group.files.count - 1 {
            selection.insert(url)
        }
    }

    var selectedBytes: UInt64 {
        switch mode {
        case .large: return largeFiles.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.bytes }
        case .old: return oldFiles.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.bytes }
        case .duplicates:
            return duplicates.reduce(0) { sum, group in sum + group.bytes * UInt64(group.files.filter { selection.contains($0) }.count) }
        }
    }

    // MARK: - Execution

    func requestRemoval() {
        let requests: [TrashRequest]
        switch mode {
        case .large: requests = makeRequests(largeFiles.filter { selection.contains($0.url) }.map { ($0.url, $0.bytes) })
        case .old: requests = makeRequests(oldFiles.filter { selection.contains($0.url) }.map { ($0.url, $0.bytes) })
        case .duplicates: requests = makeRequests(duplicates.flatMap { group in group.files.filter { selection.contains($0) }.map { ($0, group.bytes) } })
        }
        guard !requests.isEmpty else { return }

        var warnings: [String] = []
        if requests.contains(where: { protection.isPersonal($0.url) }) {
            warnings.append(tr("Includes files in Documents, Desktop or Pictures that you selected yourself."))
        }
        preview = ActionPreview(
            title: tr("Move to the Trash?"),
            message: tr("Nothing is deleted permanently. You can restore these items from the Trash or with Undo in Activity."),
            items: requests.map { PreviewItem(path: $0.url.path, bytes: $0.bytes) },
            warnings: warnings, confirmTitle: tr("Move to the Trash"),
            perform: { [weak self] in self?.execute(requests) }
        )
    }

    private func makeRequests(_ files: [(URL, UInt64)]) -> [TrashRequest] {
        // The user picked each of these by hand, so personal folders are permitted for them (and only them).
        files.map { TrashRequest(url: $0.0, bytes: $0.1, allowPersonal: true) }
    }

    private func execute(_ requests: [TrashRequest]) {
        let kind: ActionKind = mode == .duplicates ? .duplicates : .largeFiles
        model.moveToTrash(requests, kind: kind, title: tr("Files")) { [weak self] report, banner in
            guard let self = self else { return }
            let done = Set(report.trashed.map(\.originalPath))
            self.largeFiles.removeAll { done.contains($0.url.path) }
            self.oldFiles.removeAll { done.contains($0.url.path) }
            self.duplicates = self.duplicates.compactMap { group in
                let rest = group.files.filter { !done.contains($0.path) }
                return rest.count > 1 ? DuplicateGroup(id: group.id, bytes: group.bytes, files: rest) : nil
            }
            self.selection = self.selection.filter { !done.contains($0.path) }
            self.banner = banner
        }
    }

    func undo(_ id: UUID) {
        model.undo(recordID: id) { [weak self] banner in self?.banner = banner }
    }
}

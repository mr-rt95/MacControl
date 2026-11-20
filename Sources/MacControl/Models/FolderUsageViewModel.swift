//
//  FolderUsageViewModel.swift
//  MacControl
//

import Foundation
import MacControlCore

/// Drives the "What takes space" browser on the Disk screen: start in the home folder, drill down, go back up.
final class FolderUsageViewModel: ObservableObject {

    @Published private(set) var folder: URL
    @Published private(set) var entries: [FolderEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false

    let root: URL
    private let usage = FolderUsage()
    private var token = CancellationToken()

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.root = root
        self.folder = root
    }

    var canGoUp: Bool { folder.standardizedFileURL.path != root.standardizedFileURL.path }

    var totalBytes: UInt64 { entries.reduce(0) { $0 + $1.bytes } }

    func scan() { scan(folder) }

    func open(_ entry: FolderEntry) {
        guard entry.isDirectory else { return }
        scan(entry.url)
    }

    func goUp() {
        guard canGoUp else { return }
        scan(folder.deletingLastPathComponent())
    }

    func cancel() { token.cancel() }

    private func scan(_ target: URL) {
        token.cancel()
        token = CancellationToken()
        let token = self.token
        folder = target
        entries = []
        isScanning = true
        hasScanned = true

        DispatchQueue.global(qos: .utility).async { [usage] in
            usage.measure(folder: target, isCancelled: { token.isCancelled }) { entry in
                DispatchQueue.main.async {
                    guard !token.isCancelled else { return }
                    self.entries.append(entry)
                    self.entries.sort { $0.bytes > $1.bytes }
                }
            }
            DispatchQueue.main.async { if !token.isCancelled { self.isScanning = false } }
        }
    }
}

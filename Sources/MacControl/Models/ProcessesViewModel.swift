//
//  ProcessesViewModel.swift
//  MacControl
//

import Foundation
import AppKit
import MacControlCore

/// Drives the Processes screen: polite quit first, force quit only after a second confirmation.
final class ProcessesViewModel: ObservableObject {

    @Published var preview: ActionPreview?
    @Published var forceRequest: ForceQuitRequest?
    @Published var banner: Banner?
    @Published private(set) var isWorking = false

    /// Group that did not quit after the polite request.
    struct ForceQuitRequest: Identifiable {
        let id = UUID()
        let name: String
        let pids: [Int32]
        /// The processes belong to another user: ending them goes through the administrator helper.
        var viaHelper = false
    }

    private unowned let model: ManagementModel
    private let terminator = ProcessTerminator()
    private var verdictCache: [Int32: ProcessVerdict] = [:]

    init(model: ManagementModel) {
        self.model = model
    }

    /// Whether the group may be quit. Cached per leading pid, because the check makes system calls.
    func verdict(for group: ProcessGroup) -> ProcessVerdict {
        guard let pid = group.pids.first else { return .gone }
        if let cached = verdictCache[pid] { return cached }
        // Judge by what the scan already knows (name, path, owner): works for processes of other users too.
        let verdict: ProcessVerdict
        if let owner = group.ownerUID, let name = group.processName {
            verdict = ProcessSafety.verdict(name: name, path: group.executablePath, ownerUID: owner, pid: pid)
        } else {
            verdict = ProcessSafety.verdict(for: pid)
        }
        verdictCache[pid] = verdict
        return verdict
    }

    /// `true` when the group may be quit, directly or (for other users' processes) through the helper.
    func canQuit(_ group: ProcessGroup) -> Bool {
        let verdict = verdict(for: group)
        return verdict == .allowed || (verdict == .otherUser && model.helper.isUsable)
    }

    func requestQuit(_ group: ProcessGroup) {
        guard canQuit(group) else {
            banner = Banner(message: Self.explanation(for: verdict(for: group), name: group.name), isError: true)
            return
        }
        preview = ActionPreview(
            title: tr("Quit %@?", group.name),
            message: tr("Unsaved changes in %@ may be lost.", group.name),
            items: group.pids.map { PreviewItem(path: "\(group.name) (pid \($0))", bytes: 0) },
            confirmTitle: tr("Quit app"),
            perform: { [weak self] in self?.quit(group) }
        )
    }

    func forceQuit(_ request: ForceQuitRequest) {
        isWorking = true
        let client = request.viaHelper ? model.helper.commandClient() : nil
        DispatchQueue.global(qos: .userInitiated).async { [terminator] in
            if request.viaHelper {
                request.pids.forEach { _ = client?.terminate(pid: $0, force: true) }
            } else {
                _ = terminator.forceQuit(pids: request.pids)
            }
            let remaining = terminator.waitForExit(pids: request.pids, timeout: 3)
            DispatchQueue.main.async {
                self.isWorking = false
                self.banner = remaining.isEmpty
                    ? Banner(message: tr("%@ was force-quit.", request.name))
                    : Banner(message: tr("%@ is still running.", request.name), isError: true)
            }
        }
    }

    // MARK: - Private

    private func quit(_ group: ProcessGroup) {
        isWorking = true
        // Quit the application itself when there is one: its helpers exit with it, and it can save state.
        let viaHelper = verdict(for: group) == .otherUser
        let client = viaHelper ? model.helper.commandClient() : nil
        let appPIDs = group.pids.filter { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular }
        let targets = appPIDs.isEmpty ? group.pids : appPIDs

        DispatchQueue.global(qos: .userInitiated).async { [terminator] in
            var denied = false
            if viaHelper {
                for pid in targets where client?.terminate(pid: pid, force: false) == .protectedTarget { denied = true }
            } else {
                let outcomes = terminator.requestQuit(pids: targets)
                denied = outcomes.values.contains { if case .denied = $0 { return true } else { return false } }
            }
            let remaining = terminator.waitForExit(pids: group.pids, timeout: 6)
            DispatchQueue.main.async {
                self.isWorking = false
                if remaining.isEmpty {
                    self.banner = Banner(message: tr("%@ quit.", group.name))
                } else if denied {
                    self.banner = Banner(message: tr("%@ is protected and cannot be quit.", group.name), isError: true)
                } else {
                    self.forceRequest = ForceQuitRequest(name: group.name, pids: remaining, viaHelper: viaHelper)
                }
            }
        }
    }

    static func explanation(for verdict: ProcessVerdict, name: String) -> String {
        switch verdict {
        case .allowed:         return ""
        case .protectedSystem: return tr("%@ is part of macOS and is protected from quitting.", name)
        case .otherUser:       return tr("%@ belongs to another user or the system. Quitting it needs the administrator helper (see Permissions).", name)
        case .ownProcess:      return tr("This is MacControl itself.")
        case .gone:            return tr("%@ is no longer running.", name)
        }
    }
}

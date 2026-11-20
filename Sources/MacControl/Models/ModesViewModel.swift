//
//  ModesViewModel.swift
//  MacControl
//

import Foundation
import AppKit
import MacControlCore

/// Quiet / Performance modes. Modes are switched on by hand and switched back with one click;
/// no process is ever terminated by a mode.
final class ModesViewModel: ObservableObject {

    @Published private(set) var mode = PerformanceMode.normal
    /// Background processes currently held at low priority (quiet mode).
    @Published private(set) var loweredCount = 0
    /// Heavy background apps worth closing (performance mode).
    @Published private(set) var suggestions: [ProcessGroup] = []

    private let controller = PriorityController(stateURL: AppSupport.directory?.appendingPathComponent("quiet-state.json"))
    private let queue = DispatchQueue(label: "com.maccontrol.modes", qos: .utility)
    private var lastGroups: [ProcessGroup] = []
    /// The last application the user worked in. MacControl's own window does not count.
    private var workingAppPID: Int32?
    private var observer: NSObjectProtocol?

    init() {
        workingAppPID = Self.frontmostForeignPID()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if let pid = Self.frontmostForeignPID() { self?.workingAppPID = pid }
        }
    }

    deinit {
        if let observer = observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func setMode(_ newMode: PerformanceMode) {
        mode = newMode
        apply()
    }

    /// Called with every new sample so newly started processes are handled and the active app is spared.
    func update(groups: [ProcessGroup]) {
        lastGroups = groups
        guard mode != .normal else { return }
        apply()
    }

    /// Restores normal priorities (call when the app quits).
    func shutdown() {
        queue.sync { controller.restoreAll() }
    }

    // MARK: - Private

    private func apply() {
        let mode = self.mode, groups = lastGroups, front = workingAppPID
        queue.async { [controller] in
            var lowered = 0
            var suggestions: [ProcessGroup] = []

            switch mode {
            case .normal:
                controller.restoreAll()
            case .quiet:
                lowered = controller.reconcile(targets: ModePlanner.quietTargets(groups: groups, frontmostPID: front))
            case .performance:
                controller.restoreAll()
                suggestions = ModePlanner.closeSuggestions(groups: groups, frontmostPID: front) { group in
                    group.pids.first.map { ProcessSafety.verdict(for: $0) == .allowed } ?? false
                }
            }
            DispatchQueue.main.async {
                self.loweredCount = lowered
                self.suggestions = suggestions
            }
        }
    }

    private static func frontmostForeignPID() -> Int32? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app.processIdentifier
    }
}

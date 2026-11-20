//
//  AppsViewModel.swift
//  MacControl
//

import Foundation
import MacControlCore

/// Drives the Apps screen: installed apps, leftovers, and removal.
final class AppsViewModel: ObservableObject {

    enum Sort: String, CaseIterable { case name, size, lastUsed }

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isScanning = false
    @Published var selected: InstalledApp?
    @Published private(set) var plan: UninstallPlan?
    @Published private(set) var isPlanning = false
    @Published var keptLeftovers = Set<URL>()
    @Published var preview: ActionPreview?
    @Published var banner: Banner?
    @Published var sort = Sort.size
    @Published var showOnlyUnused = false

    /// Apps not opened for this long count as unused.
    static let unusedAfter: TimeInterval = 180 * 86_400

    private unowned let model: ManagementModel
    private let scanner = InstalledAppsScanner()
    private lazy var uninstaller = AppUninstaller(trasher: model.trasher)

    init(model: ManagementModel) {
        self.model = model
    }

    var visibleApps: [InstalledApp] {
        var list = apps
        if showOnlyUnused {
            let cutoff = Date().addingTimeInterval(-Self.unusedAfter)
            list = list.filter { $0.isRemovable && ($0.lastUsed ?? .distantPast) < cutoff }
        }
        switch sort {
        case .name:     return list
        case .size:     return list.sorted { $0.bytes > $1.bytes }
        case .lastUsed: return list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        DispatchQueue.global(qos: .utility).async { [scanner] in
            let apps = scanner.scan()
            DispatchQueue.main.async {
                self.apps = apps
                self.isScanning = false
            }
        }
    }

    /// Finds leftovers for the chosen app. All are kept ticked by default; the user can untick any.
    func select(_ app: InstalledApp?) {
        selected = app
        plan = nil
        guard let app = app, app.isRemovable else { return }
        isPlanning = true
        DispatchQueue.global(qos: .userInitiated).async { [uninstaller] in
            let plan = uninstaller.plan(for: app)
            DispatchQueue.main.async {
                guard self.selected == app else { return }
                self.plan = plan
                // System-wide leftovers are ticked too when the administrator helper can remove them.
                self.keptLeftovers = Set((self.helperUsable ? plan.leftovers : plan.removableLeftovers).map(\.url))
                self.isPlanning = false
            }
        }
    }

    func requestUninstall() {
        guard let plan = plan else { return }
        let leftovers = (helperUsable ? plan.leftovers : plan.removableLeftovers).filter { keptLeftovers.contains($0.url) }
        var items = [PreviewItem(path: plan.app.url.path, bytes: plan.app.bytes)]
        items += leftovers.map { PreviewItem(path: $0.url.path, bytes: $0.bytes) }

        var warnings: [String] = []
        if !helperUsable, !plan.skippedLeftovers.isEmpty {
            warnings.append(tr("%@ system-wide files need administrator rights and will be left in place.", "\(plan.skippedLeftovers.count)"))
        }
        if helperUsable, leftovers.contains(where: \.requiresAdministrator) {
            warnings.append(tr("System-wide files are moved by the administrator helper into a protected holding folder (kept 30 days, restorable with Undo)."))
        }
        preview = ActionPreview(
            title: tr("Remove %@?", plan.app.name),
            message: tr("The app is closed first, then it and the items below are moved to the Trash."),
            items: items, warnings: warnings, confirmTitle: tr("Move to the Trash"),
            perform: { [weak self] in self?.uninstall(plan, leftovers: leftovers) }
        )
    }

    private func uninstall(_ plan: UninstallPlan, leftovers: [Leftover]) {
        let client = model.helper.commandClient()
        let remover: ((Leftover) -> Result<String, HelperFailure>)? = client.map { client in
            { leftover in client.moveLeftover(path: leftover.url.path, bundleIdentifier: plan.app.bundleIdentifier ?? "") }
        }
        DispatchQueue.global(qos: .userInitiated).async { [uninstaller] in
            let result = Result { try uninstaller.uninstall(plan, selectedLeftovers: leftovers, systemRemover: remover) }
            DispatchQueue.main.async {
                self.model.bumpLog()
                switch result {
                case .success(let report):
                    self.banner = ManagementModel.banner(for: report)
                    self.apps.removeAll { $0.url == plan.app.url }
                    self.selected = nil
                    self.plan = nil
                case .failure(let error):
                    let message = (error as? UninstallError) == .appStillRunning
                        ? tr("%@ did not quit. Close it yourself and try again.", plan.app.name)
                        : tr("%@ cannot be removed.", plan.app.name)
                    self.banner = Banner(message: message, isError: true)
                }
            }
        }
    }

    var helperUsable: Bool { model.helper.isUsable }

    func undo(_ id: UUID) {
        model.undo(recordID: id) { [weak self] banner in self?.banner = banner }
    }
}

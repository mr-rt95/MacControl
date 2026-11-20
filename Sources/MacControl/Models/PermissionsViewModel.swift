//
//  PermissionsViewModel.swift
//  MacControl
//

import Foundation
import AppKit

/// One permission MacControl may need, with what it is used for and how to grant it.
struct PermissionItem: Identifiable {

    struct Action: Identifiable {
        let title: String
        let perform: () -> Void
        var id: String { title }
    }

    let id: String
    let title: String
    /// Features that rely on it.
    let usedFor: String
    let status: PermissionStatus
    let actions: [Action]
}

/// Collects the state of every permission for the Permissions screen. Status is re-read whenever the user
/// returns from System Settings.
final class PermissionsViewModel: ObservableObject {

    @Published private(set) var items: [PermissionItem] = []

    private let notifications: NotificationService
    private let loginLaunch: LoginLaunchService
    private var notificationStatus = PermissionStatus.unknown
    private var observer: NSObjectProtocol?

    init(notifications: NotificationService, loginLaunch: LoginLaunchService) {
        self.notifications = notifications
        self.loginLaunch = loginLaunch
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        PermissionChecker.notifications { [weak self] status in
            self?.notificationStatus = status
            self?.rebuild()
        }
        rebuild()
    }

    // MARK: - Items

    private func rebuild() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fullDisk = PermissionChecker.fullDiskAccess()
            let systemEvents = PermissionChecker.automation(bundleIdentifier: "com.apple.systemevents")
            let finder = PermissionChecker.automation(bundleIdentifier: "com.apple.finder")
            DispatchQueue.main.async {
                self.items = self.makeItems(fullDisk: fullDisk, systemEvents: systemEvents, finder: finder)
            }
        }
    }

    private func makeItems(fullDisk: PermissionStatus, systemEvents: PermissionStatus, finder: PermissionStatus) -> [PermissionItem] {
        typealias Action = PermissionItem.Action
        return [
            PermissionItem(
                id: "fullDisk", title: tr("Full Disk Access"),
                usedFor: tr("Size of the Trash, iPhone backups and other protected folders in Cleanup."),
                status: fullDisk,
                actions: [Action(title: tr("Open System Settings"), perform: { PermissionChecker.open(.fullDiskAccess) }),
                          Action(title: tr("Show MacControl in Finder"), perform: { PermissionChecker.revealApp() })]),
            PermissionItem(
                id: "automationSystemEvents", title: tr("Automation: System Events"),
                usedFor: tr("Reading and changing login items."),
                status: systemEvents,
                actions: [Action(title: tr("Ask now"), perform: { [weak self] in
                              PermissionChecker.requestAutomation(bundleIdentifier: "com.apple.systemevents") { _ in self?.refresh() }
                          }),
                          Action(title: tr("Open System Settings"), perform: { PermissionChecker.open(.automation) })]),
            PermissionItem(
                id: "automationFinder", title: tr("Automation: Finder"),
                usedFor: tr("Emptying the Trash through Finder."),
                status: finder,
                actions: [Action(title: tr("Ask now"), perform: { [weak self] in
                              PermissionChecker.requestAutomation(bundleIdentifier: "com.apple.finder") { _ in self?.refresh() }
                          }),
                          Action(title: tr("Open System Settings"), perform: { PermissionChecker.open(.automation) })]),
            PermissionItem(
                id: "notifications", title: tr("Notifications"),
                usedFor: tr("Alerts about overheating, low disk space, memory and frozen apps."),
                status: notificationStatus,
                actions: [notificationStatus == .notDetermined
                          ? Action(title: tr("Allow"), perform: { [weak self] in
                                self?.notifications.requestAuthorization { _ in self?.refresh() }
                            })
                          : Action(title: tr("Open System Settings"), perform: { PermissionChecker.open(.notifications) })]),
            PermissionItem(
                id: "files", title: tr("Files and Folders"),
                usedFor: tr("Looking for large files and duplicates in Downloads, Documents and Desktop. macOS asks the first time a folder is read."),
                status: .unknown,
                actions: [Action(title: tr("Open System Settings"), perform: { PermissionChecker.open(.filesAndFolders) })]),
            PermissionItem(
                id: "login", title: tr("Launch at login"),
                usedFor: tr("Keeps the menu bar item available after a restart."),
                status: loginLaunch.isEnabled ? .granted : .notDetermined,
                actions: [Action(title: loginLaunch.isEnabled ? tr("Turn off") : tr("Turn on"), perform: { [weak self] in
                    guard let self = self else { return }
                    self.loginLaunch.setEnabled(!self.loginLaunch.isEnabled)
                    self.refresh()
                })])
        ]
    }
}

//
//  AppDelegate.swift
//  MacControl
//

import AppKit
import SwiftUI
import Combine
import MacControlCore

/// Wires the monitoring service to the main window and the menu bar item,
/// and adapts the polling rate to window visibility.
final class AppDelegate: NSObject, NSApplicationDelegate {

    let monitoring = MonitoringService()
    let helper = HelperManager()
    private lazy var management = ManagementModel(helper: helper)
    private(set) lazy var permissions = PermissionsViewModel(notifications: notifications, loginLaunch: loginLaunch)
    private let navigation = NavigationModel()
    let notifications = NotificationService()
    let loginLaunch = LoginLaunchService()
    private let planner = NotificationPlanner()
    private var snapshotObserver: AnyCancellable?
    private let settings = AppSettings.shared
    private var statusItemController: StatusItemController?
    private var mainWindow: NSWindow?
    private var settingsObserver: AnyCancellable?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        applySettings()
        settingsObserver = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySettings() }
        monitoring.supplementalProcesses = { [helper] in helper.supplementalProcesses() }
        monitoring.start()

        statusItemController = StatusItemController(
            monitoring: monitoring,
            settings: settings,
            modes: management.modes,
            openApp: { [weak self] in self?.showMainWindow() }
        )

        notifications.onOpen = { [weak self] screen in
            self?.navigation.selection = screen
            self?.showMainWindow()
        }
        // One step behind the sample so `analysis` is already updated when it is read.
        snapshotObserver = monitoring.$snapshot
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.handle(snapshot) }

        NotificationCenter.default.addObserver(
            self, selector: #selector(updatePollingMode),
            name: NSApplication.didChangeOcclusionStateNotification, object: nil
        )

        showMainWindow()
    }

    /// Saves history and journal so nothing is lost when the app quits.
    func applicationWillTerminate(_ notification: Notification) {
        management.modes.shutdown()      // never leave processes at low priority behind
        monitoring.flush()
    }

    /// The app lives on in the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - Window

    private func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeMainWindow()
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updatePollingMode()
    }

    private func makeMainWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: RootView().environmentObject(monitoring).environmentObject(management).environmentObject(navigation)
                                                .environmentObject(permissions))
        let window = NSWindow(contentViewController: hosting)
        window.title = "MacControl"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false          // keep it alive so it can be reopened
        window.setContentSize(NSSize(width: 1020, height: 700))
        window.setFrameAutosaveName("MainWindow")
        window.center()
        return window
    }

    // MARK: - Reacting to new samples

    /// Feeds the modes and, when enabled, turns findings into notifications.
    private func handle(_ snapshot: SystemSnapshot) {
        management.modes.update(groups: snapshot.processGroups)

        guard settings.notificationsEnabled else { return }
        planner.cooldown = TimeInterval(settings.notificationCooldownMinutes * 60)
        let alerts = planner.plan(findings: monitoring.analysis.findings, enabled: settings.enabledAlertKinds)
        for alert in alerts {
            let pids = snapshot.processGroups.first { $0.name == alert.appName }?.pids ?? []
            notifications.deliver(alert, pids: pids)
        }
    }

    // MARK: - Settings

    /// Passes the user's limits to the diagnostics engine and the journal.
    private func applySettings() {
        var thresholds = DiagnosticsThresholds()
        let warning = Double(settings.diskWarningPercent) / 100
        thresholds.diskWarningFreeFraction = warning
        thresholds.diskSeriousFreeFraction = warning * 2 / 3
        monitoring.configure(thresholds: thresholds, retentionDays: settings.retentionDays)
    }

    // MARK: - Polling rate

    /// Samples every second while any window is visible, and every few seconds otherwise.
    @objc private func updatePollingMode() {
        let visible = NSApp.occlusionState.contains(.visible)
        monitoring.setMode(visible ? .foreground : .background)
    }
}

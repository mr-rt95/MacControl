//
//  NotificationService.swift
//  MacControl
//

import Foundation
import UserNotifications
import MacControlCore

/// Delivers system notifications and handles their buttons.
///
/// The planner (core) decides *what* deserves a notification and suppresses repeats; this class only words
/// and shows them. Notification center is unavailable outside an app bundle, so everything is optional-safe.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    private enum Action {
        static let show = "maccontrol.show"
        static let quit = "maccontrol.quit"
        static let plainCategory = "maccontrol.alert"
        static let appCategory = "maccontrol.alert.app"
    }

    /// Called when the user taps a notification: open this screen.
    var onOpen: ((Screen) -> Void)?

    private let center: UNUserNotificationCenter?
    private let terminator = ProcessTerminator()

    override init() {
        center = Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
        registerCategories()
    }

    // MARK: - Permission

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard let center = center else { completion(false); return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    // MARK: - Delivery

    /// Shows one notification. `pids` are the processes of the involved app, for the "Quit app" button.
    func deliver(_ alert: PlannedAlert, pids: [Int32]) {
        guard let center = center else { return }
        let text = Self.text(for: alert)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.categoryIdentifier = pids.isEmpty ? Action.plainCategory : Action.appCategory
        content.userInfo = ["screen": Self.screen(for: alert).rawValue, "pids": pids.map { Int($0) }]
        // A fixed identifier replaces an older notification of the same kind instead of stacking them.
        center.add(UNNotificationRequest(identifier: alert.kind.rawValue, content: content, trigger: nil))
    }

    // MARK: - Wording

    static func text(for alert: PlannedAlert) -> (title: String, body: String) {
        let m = alert.metrics
        switch alert.kind {
        case .overheating:
            var body = m["temperature"].map { tr("CPU temperature is %@.", Formatters.temperature($0)) } ?? tr("macOS reports a serious thermal state.")
            if let app = alert.appName { body += " " + tr("The main load comes from %@.", app) }
            return (tr("Your Mac is overheating"), body)
        case .lowDisk:
            return (tr("The disk is almost full"),
                    tr("Only %@ left (%@). macOS needs free space for swap and temporary files.",
                       Formatters.bytes(UInt64(m["free"] ?? 0)), Formatters.percent(m["freeFraction"] ?? 0)))
        case .memoryPressure:
            return (tr("Memory is running low"), tr("Close apps and browser tabs you are not using."))
        case .frozenApp:
            let name = alert.appName ?? tr("An app")
            return (tr("%@ may be frozen", name),
                    tr("It has used almost a full processor core for %@.", FindingPresenter.duration(m["duration"] ?? 0)))
        case .longHighLoad:
            return (tr("The processor has been busy for a long time"),
                    tr("Load has been %@ for %@.", Formatters.percent(m["load"] ?? 0), FindingPresenter.duration(m["duration"] ?? 0)))
        }
    }

    static func screen(for alert: PlannedAlert) -> Screen {
        switch alert.kind {
        case .overheating, .memoryPressure, .longHighLoad: return .diagnosis
        case .lowDisk: return .cleanup
        case .frozenApp: return .processes
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while MacControl is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let pids = (info["pids"] as? [Int])?.map { Int32($0) } ?? []

        if response.actionIdentifier == Action.quit, !pids.isEmpty {
            // Polite quit only; ProcessTerminator re-checks that the process may be quit at all.
            DispatchQueue.global(qos: .userInitiated).async { [terminator] in _ = terminator.requestQuit(pids: pids) }
        } else if let raw = info["screen"] as? String, let screen = Screen(rawValue: raw) {
            DispatchQueue.main.async { self.onOpen?(screen) }
        }
        completionHandler()
    }

    private func registerCategories() {
        let show = UNNotificationAction(identifier: Action.show, title: tr("Show details"), options: [.foreground])
        let quit = UNNotificationAction(identifier: Action.quit, title: tr("Quit app"), options: [])
        center?.setNotificationCategories([
            UNNotificationCategory(identifier: Action.plainCategory, actions: [show], intentIdentifiers: []),
            UNNotificationCategory(identifier: Action.appCategory, actions: [show, quit], intentIdentifiers: [])
        ])
    }
}

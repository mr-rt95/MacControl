//
//  PermissionChecker.swift
//  MacControl
//

import Foundation
import AppKit
import UserNotifications

enum PermissionStatus: Equatable {
    case granted
    case denied
    /// macOS has not asked the user yet.
    case notDetermined
    /// Cannot be detected without triggering a prompt.
    case unknown
}

/// Reads the state of macOS privacy permissions without ever triggering a permission prompt.
enum PermissionChecker {

    /// Full Disk Access: only a process with it can open the system TCC database.
    static func fullDiskAccess() -> PermissionStatus {
        let descriptor = Darwin.open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if descriptor >= 0 { Darwin.close(descriptor); return .granted }
        return errno == EPERM || errno == EACCES ? .denied : .unknown
    }

    /// Automation permission for controlling another app. Never asks the user.
    ///
    /// macOS can only answer while the target app is running. System Events is started on demand, so when it is not
    /// running it is launched quietly in the background (no window, not activated) and the check is repeated.
    /// Call this off the main thread: it may wait a moment for the launch.
    static func automation(bundleIdentifier: String) -> PermissionStatus {
        var status = determineAutomation(bundleIdentifier: bundleIdentifier)
        if status == .unknown, launchInBackground(bundleIdentifier: bundleIdentifier) {
            status = determineAutomation(bundleIdentifier: bundleIdentifier)
        }
        return status
    }

    private static func determineAutomation(bundleIdentifier: String) -> PermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let descriptor = target.aeDesc else { return .unknown }
        let wildcard: UInt32 = 0x2A2A2A2A   // '****'
        switch AEDeterminePermissionToAutomateTarget(descriptor, wildcard, wildcard, false) {
        case noErr:  return .granted
        case -1743:  return .denied          // errAEEventNotPermitted
        case -1744:  return .notDetermined   // errAEEventWouldRequireUserConsent
        default:     return .unknown         // e.g. procNotFound (-600): the target is not running
        }
    }

    /// Starts the app without showing it and waits up to three seconds for it to appear.
    private static func launchInBackground(bundleIdentifier: String) -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)

        for _ in 0..<30 {
            if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    static func notifications(completion: @escaping (PermissionStatus) -> Void) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { completion(.unknown); return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: PermissionStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = .granted
            case .denied: status = .denied
            case .notDetermined: status = .notDetermined
            @unknown default: status = .unknown
            }
            DispatchQueue.main.async { completion(status) }
        }
    }

    /// Shows the macOS Automation prompt for an app, on the user's explicit request.
    ///
    /// Uses the system's own permission call with "ask the user" enabled, which is what makes the dialog appear
    /// reliably (an AppleScript sent from a background queue may fail silently). The call blocks until the user
    /// answers, so it runs on a background queue and `completion` is called on the main queue afterwards.
    static func requestAutomation(bundleIdentifier: String, completion: @escaping (PermissionStatus) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // The target must be running for macOS to evaluate (and ask about) the permission.
            _ = launchInBackground(bundleIdentifier: bundleIdentifier)
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            let wildcard: UInt32 = 0x2A2A2A2A
            if let descriptor = target.aeDesc {
                _ = AEDeterminePermissionToAutomateTarget(descriptor, wildcard, wildcard, true)
            }
            let status = determineAutomation(bundleIdentifier: bundleIdentifier)
            DispatchQueue.main.async { completion(status) }
        }
    }

    // MARK: - System Settings panes

    enum Pane {
        case fullDiskAccess, automation, notifications, filesAndFolders

        var url: URL {
            switch self {
            case .fullDiskAccess:  return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
            case .automation:      return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
            case .filesAndFolders: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
            case .notifications:   return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
            }
        }
    }

    static func open(_ pane: Pane) { NSWorkspace.shared.open(pane.url) }

    /// Shows MacControl in Finder, handy for dragging it into the Full Disk Access list.
    static func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
}

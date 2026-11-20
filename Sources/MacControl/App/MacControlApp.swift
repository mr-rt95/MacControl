//
//  MacControlApp.swift
//  MacControl
//

import SwiftUI

/// Application entry point.
///
/// The main window and the menu bar item are owned by `AppDelegate`, which lets the
/// window be closed and reopened while the app keeps running in the menu bar.
/// SwiftUI only provides the Settings scene here.
@main
struct MacControlApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: AppSettings.shared, monitoring: appDelegate.monitoring,
                         notifications: appDelegate.notifications, launchAtLogin: appDelegate.loginLaunch)
        }
    }
}

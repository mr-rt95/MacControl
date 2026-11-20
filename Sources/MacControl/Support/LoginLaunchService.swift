//
//  LoginLaunchService.swift
//  MacControl
//

import Foundation
import ServiceManagement

/// "Launch at login", so the menu bar item is there after a restart.
///
/// macOS 13+ uses `SMAppService`. macOS 12 has no equivalent for a plain app, so a per-user LaunchAgent
/// is written instead; it is removed again when the option is switched off.
final class LoginLaunchService: ObservableObject {

    @Published private(set) var isEnabled = false

    private let agentURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.maccontrol.app.plist")

    init() {
        isEnabled = currentState()
    }

    /// Turns the option on or off. Returns `false` if macOS refused (the state is re-read either way).
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        var succeeded = true
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                succeeded = false
            }
        } else {
            succeeded = enabled ? writeAgent() : removeAgent()
        }
        isEnabled = currentState()
        return succeeded
    }

    // MARK: - Private

    private func currentState() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    private func writeAgent() -> Bool {
        let plist: [String: Any] = [
            "Label": "com.maccontrol.app",
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return false }
        try? FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: agentURL, options: .atomic)) != nil
    }

    private func removeAgent() -> Bool {
        (try? FileManager.default.removeItem(at: agentURL)) != nil || !FileManager.default.fileExists(atPath: agentURL.path)
    }
}

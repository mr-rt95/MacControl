//
//  HelperManager.swift
//  MacControl
//

import Foundation
import AppKit
import ServiceManagement
import MacControlCore

/// Installs, removes and talks to the privileged helper daemon.
///
/// The helper only works for a properly signed build (macOS refuses to register a daemon for an ad-hoc signed
/// app, and the helper itself refuses clients it cannot verify), so an unsigned build reports `.unsigned`.
final class HelperManager: ObservableObject {

    enum Status: Equatable {
        /// Built without a signing certificate: the helper cannot be installed.
        case unsigned
        case unsupportedOS
        case notRegistered
        /// Registered, waiting for the user to allow it in System Settings ▸ Login Items.
        case requiresApproval
        case enabled
        case failed(String)
    }

    @Published private(set) var status: Status = .unsigned
    /// `true` when the helper answered a live request with a matching protocol version.
    @Published private(set) var isReachable = false

    let trust: SigningTrust?
    private let client: HelperClient
    private let processClient: HelperClient
    private let queue = DispatchQueue(label: "com.maccontrol.helper.status", qos: .utility)

    private let usableLock = NSLock()
    private var usable = false
    private var retryProcessesAfter = Date.distantPast
    private var activationObserver: NSObjectProtocol?

    init(trust: SigningTrust? = SigningTrust.current) {
        self.trust = trust
        self.client = HelperClient(trust: trust, timeout: 30)
        self.processClient = HelperClient(trust: trust, timeout: 2)
        // The user approves the helper in System Settings; re-read its state when they come back to the app.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    deinit {
        if let observer = activationObserver { NotificationCenter.default.removeObserver(observer) }
    }

    /// `true` when privileged actions can be used right now.
    var isUsable: Bool { status == .enabled && isReachable }

    /// The client for privileged actions, or `nil` when the helper is not available.
    func commandClient() -> HelperClient? { isUsable ? client : nil }

    // MARK: - Status

    func refresh() {
        let newStatus = currentStatus()
        DispatchQueue.main.async { self.status = newStatus }
        guard newStatus == .enabled else {
            setUsable(false)
            DispatchQueue.main.async { self.isReachable = false }
            return
        }
        queue.async { [client] in
            let reachable = client.isReachable()
            self.setUsable(reachable)
            DispatchQueue.main.async { self.isReachable = reachable }
        }
    }

    private func currentStatus() -> Status {
        guard trust != nil else { return .unsigned }
        guard #available(macOS 13.0, *) else { return .unsupportedOS }
        switch SMAppService.daemon(plistName: HelperConstants.daemonPlistName).status {
        case .enabled:          return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered:    return .notRegistered
        case .notFound:         return .failed("not found")
        @unknown default:       return .failed("unknown")
        }
    }

    // MARK: - Install / remove

    /// Registers the daemon. macOS then asks for approval in System Settings ▸ Login Items (and may ask for a password).
    func install() {
        guard #available(macOS 13.0, *), trust != nil else { return }
        do {
            try SMAppService.daemon(plistName: HelperConstants.daemonPlistName).register()
        } catch {
            DispatchQueue.main.async { self.status = .failed(error.localizedDescription) }
            return
        }
        refresh()
    }

    func uninstall() {
        guard #available(macOS 13.0, *) else { return }
        try? SMAppService.daemon(plistName: HelperConstants.daemonPlistName).unregister()
        refresh()
    }

    func openApprovalSettings() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
    }

    // MARK: - Processes only an administrator can see

    /// Samples root's and other users' processes through the helper. Called from the sampling queue each tick,
    /// so it is quick (2 s limit) and backs off for a minute after a failure.
    func supplementalProcesses() -> [ProcessSample] {
        usableLock.lock()
        let allowed = usable && Date() >= retryProcessesAfter
        usableLock.unlock()
        guard allowed else { return [] }

        guard let samples = processClient.processSamples() else {
            usableLock.lock()
            retryProcessesAfter = Date().addingTimeInterval(60)
            usableLock.unlock()
            return []
        }
        return samples.filter { $0.uid != getuid() }
    }

    private func setUsable(_ value: Bool) {
        usableLock.lock()
        usable = value
        usableLock.unlock()
    }
}

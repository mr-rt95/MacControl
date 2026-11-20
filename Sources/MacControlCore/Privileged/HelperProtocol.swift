//
//  HelperProtocol.swift
//  MacControlCore
//

import Foundation

/// Names shared by the app and the helper daemon.
public enum HelperConstants {
    /// Mach service the helper listens on (also the bundle identifier of the helper).
    public static let machServiceName = "com.maccontrol.helper"
    /// Launchd plist inside the app bundle: `Contents/Library/LaunchDaemons/<name>`.
    public static let daemonPlistName = "com.maccontrol.helper.plist"
    public static let appBundleIdentifier = "com.maccontrol.app"
    /// Bumped whenever the protocol changes, so a stale helper is detected after an app update.
    public static let protocolVersion = 1
    /// Info.plist key holding the Apple Developer Team ID the app and helper are signed with.
    public static let teamIDKey = "MCSigningTeamID"
}

/// What the helper can do as root. Deliberately a short whitelist: the helper never runs arbitrary
/// commands or paths, and re-validates every request itself instead of trusting the app.
///
/// Every reply is `(success, errorCode?)`; error codes are the raw values of `HelperFailure`.
@objc public protocol MacControlHelperProtocol {

    /// Protocol version of the running helper.
    func protocolVersion(reply: @escaping (Int) -> Void)

    /// Deletes a local Time Machine snapshot, e.g. `com.apple.TimeMachine.2026-11-20-123456.local`.
    func deleteTimeMachineSnapshot(_ name: String, reply: @escaping (Bool, String?) -> Void)

    /// Moves a system-wide leftover of an uninstalled app (`/Library/...`) into the helper's quarantine.
    /// The reply carries the quarantine id on success, so the move can be undone.
    func moveSystemLeftover(_ path: String, bundleIdentifier: String, reply: @escaping (String?, String?) -> Void)

    /// Puts a quarantined item back where it came from.
    func restoreQuarantined(_ id: String, reply: @escaping (Bool, String?) -> Void)

    /// Disables or re-enables a system launch daemon in `/Library/LaunchDaemons` without deleting it.
    func setDaemonEnabled(label: String, plistPath: String, enabled: Bool, reply: @escaping (Bool, String?) -> Void)

    /// Asks a process of another user (or root) to quit (`SIGTERM`), or kills it (`SIGKILL`) when `force` is set.
    func terminateProcess(_ pid: Int32, force: Bool, reply: @escaping (Bool, String?) -> Void)

    /// Resource use of every process on the Mac (including root's, which a normal user cannot read),
    /// as JSON-encoded `[ProcessSample]`. Rates are zero on the first call and valid from the second.
    func readProcesses(reply: @escaping (Data?, String?) -> Void)

    /// Selected lines of `powermetrics` (CPU frequency, thermal state). Needs root.
    func readPowerMetrics(reply: @escaping (String?, String?) -> Void)
}

/// Why a privileged request was refused or failed.
public enum HelperFailure: String, Error, Equatable {
    /// Malformed input (bad name, label, path shape).
    case invalidArgument
    /// The target is outside what the helper may touch.
    case notAllowed
    /// The target is a protected system item or process.
    case protectedTarget
    case notFound
    /// The underlying tool or file operation failed.
    case operationFailed
    case timedOut
    /// The helper could not be reached or verified.
    case helperUnavailable
}

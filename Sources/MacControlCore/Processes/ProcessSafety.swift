//
//  ProcessSafety.swift
//  MacControlCore
//

import Foundation

/// Whether a process may be asked to quit.
public enum ProcessVerdict: Equatable {
    case allowed
    /// macOS component or a process whose loss would destabilize the session.
    case protectedSystem
    /// Belongs to another user (or root): needs the privileged helper.
    case otherUser
    /// This app itself.
    case ownProcess
    /// The process no longer exists.
    case gone
}

/// Rules that keep the user from terminating processes that must keep running.
public enum ProcessSafety {

    /// Names of processes that are never terminated. Compiled in, not user-configurable.
    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Dock", "SystemUIServer", "Finder",
        "cfprefsd", "coreaudiod", "coreservicesd", "launchservicesd", "distnoted", "notifyd", "logd",
        "mds", "mds_stores", "mdworker", "securityd", "trustd", "tccd", "opendirectoryd", "fseventsd",
        "powerd", "configd", "diskarbitrationd", "UserEventAgent", "hidd", "bluetoothd", "airportd",
        "syslogd", "ControlCenter", "NotificationCenter", "universalaccessd"
    ]

    /// Judges a process by name, executable path and owner.
    /// Pure: used by `verdict(for:)` and directly by the unit tests.
    public static func verdict(name: String, path: String?, ownerUID: UInt32?, pid: Int32,
                               currentUID: UInt32 = getuid(), ownPID: Int32 = getpid()) -> ProcessVerdict {
        if pid <= 1 { return .protectedSystem }
        if pid == ownPID { return .ownProcess }
        if protectedNames.contains(name) { return .protectedSystem }
        // Background components of macOS (not the user-facing apps in /System/Applications).
        if let path = path, path.hasPrefix("/System/Library/") || path.hasPrefix("/usr/libexec/") { return .protectedSystem }
        // Command-line system binaries; Homebrew tools in /usr/local are the user's own and stay quit-able.
        if let path = path, path.hasPrefix("/usr/sbin/") || path.hasPrefix("/usr/bin/") ||
            path.hasPrefix("/sbin/") || path.hasPrefix("/bin/") || path.hasPrefix("/Library/Apple/") {
            return .protectedSystem
        }
        // Apps shipped in /System/Applications (Safari, Mail, …) are user-facing and may be quit politely.
        guard let owner = ownerUID else { return .gone }
        if owner != currentUID { return .otherUser }
        return .allowed
    }

    /// Looks up the live process and judges it.
    public static func verdict(for pid: Int32) -> ProcessVerdict {
        if pid <= 1 { return .protectedSystem }
        guard let name = ProcessMonitor.processName(pid: pid) else {
            // Unreadable but alive means it belongs to someone else; only a vanished pid is "gone".
            return (kill(pid, 0) == 0 || errno == EPERM) ? .otherUser : .gone
        }
        let owner = ProcessMonitor.owner(pid: pid)
        return verdict(name: name, path: ProcessMonitor.executablePath(pid: pid),
                       ownerUID: owner == UInt32.max ? nil : owner, pid: pid)
    }
}

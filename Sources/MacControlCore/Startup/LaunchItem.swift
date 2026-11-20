//
//  LaunchItem.swift
//  MacControlCore
//

import Foundation

/// Where a launchd job is defined.
public enum LaunchScope: String, Equatable {
    case userAgent       // ~/Library/LaunchAgents
    case globalAgent     // /Library/LaunchAgents
    case globalDaemon    // /Library/LaunchDaemons
    case system          // /System/Library/Launch*: Apple's own, shown for information only

    /// Changing the state of global items needs administrator rights (privileged helper).
    /// Global agents run in the user's own launchd domain, so the user can switch them without administrator rights.
    public var requiresAdministrator: Bool { self == .globalDaemon || self == .system }
}

/// How safe it is to stop a background service.
public enum ServiceSafety: String, Equatable {
    case safe       // can be disabled without side effects
    case caution    // disabling stops a feature the user may rely on
    case system     // part of macOS; shown for information only
    case unknown
}

public enum StartupImpact: Int, Comparable, Equatable {
    case low = 0, medium, high

    public static func < (lhs: StartupImpact, rhs: StartupImpact) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A launchd agent or daemon found on disk.
public struct LaunchItem: Identifiable, Equatable {

    public let label: String
    public let plistURL: URL
    public let scope: LaunchScope
    public let program: String?
    public let runsAtLoad: Bool
    public let keepsAlive: Bool
    public var isDisabled: Bool
    /// Process id when the job is running now.
    public var pid: Int32?
    public var cpuPercent: Double = 0
    public var memoryBytes: UInt64 = 0

    public var id: String { plistURL.path }
    public var isRunning: Bool { pid != nil }

    /// Vendor guessed from the reverse-DNS label ("com.google.keystone" → "google").
    public var vendor: String {
        let parts = label.split(separator: ".")
        return parts.count >= 2 ? String(parts[1]) : label
    }

    public var isApple: Bool { label.hasPrefix("com.apple.") }

    public var safety: ServiceSafety { ServiceKnowledge.info(for: label)?.safety ?? (isApple ? .system : .unknown) }

    /// Rough effect on login time, from what the job costs while running and whether it never stops.
    public var impact: StartupImpact {
        guard runsAtLoad || keepsAlive else { return .low }
        if memoryBytes > 300_000_000 || cpuPercent > 10 { return .high }
        if memoryBytes > 80_000_000 || cpuPercent > 1 || keepsAlive { return .medium }
        return .low
    }
}

/// An item of System Settings ▸ Login Items.
public struct LoginItem: Identifiable, Codable, Equatable {
    public let name: String
    public let path: String
    public var id: String { path }
}

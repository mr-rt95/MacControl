//
//  InstalledApp.swift
//  MacControlCore
//

import Foundation

public struct InstalledApp: Identifiable, Equatable {
    public let url: URL
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let bytes: UInt64
    /// Date the app was last opened (Spotlight). `nil` if it was never opened or the date is unknown.
    public let lastUsed: Date?
    /// Set for apps that must not be removed (Apple's built-in apps).
    public let protection: ProtectionReason?

    public var id: URL { url }
    public var isRemovable: Bool { protection == nil }

    public init(url: URL, name: String, bundleIdentifier: String?, version: String?, bytes: UInt64,
                lastUsed: Date?, protection: ProtectionReason?) {
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.bytes = bytes
        self.lastUsed = lastUsed
        self.protection = protection
    }
}

/// A file that an application left behind.
public struct Leftover: Identifiable, Equatable {
    public let url: URL
    public let bytes: UInt64
    /// `true` when it lives in the system-wide `/Library` and cannot be removed without administrator rights.
    public let requiresAdministrator: Bool

    public var id: URL { url }
}

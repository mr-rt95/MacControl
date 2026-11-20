//
//  ServiceKnowledge.swift
//  MacControlCore
//

import Foundation

/// A short explanation of a well-known background service.
public struct ServiceInfo: Equatable {
    /// English text, used as a localization key by the UI.
    public let summary: String
    public let safety: ServiceSafety
}

/// Reference of known services, matched by label prefix. Grows as the project evolves.
public enum ServiceKnowledge {

    private static let table: [(prefix: String, info: ServiceInfo)] = [
        ("com.google.keystone", ServiceInfo(summary: "Google software updater", safety: .safe)),
        ("com.google.GoogleUpdater", ServiceInfo(summary: "Google software updater", safety: .safe)),
        ("com.microsoft.update", ServiceInfo(summary: "Microsoft AutoUpdate", safety: .safe)),
        ("com.adobe.", ServiceInfo(summary: "Adobe background services and updater", safety: .caution)),
        ("com.dropbox", ServiceInfo(summary: "Dropbox file sync", safety: .caution)),
        ("com.spotify", ServiceInfo(summary: "Spotify helper", safety: .safe)),
        ("us.zoom", ServiceInfo(summary: "Zoom updater and helper", safety: .safe)),
        ("com.oracle.java", ServiceInfo(summary: "Java updater", safety: .safe)),
        ("com.valvesoftware", ServiceInfo(summary: "Steam helper", safety: .safe)),
        ("com.docker", ServiceInfo(summary: "Docker background services", safety: .caution)),
        ("org.virtualbox", ServiceInfo(summary: "VirtualBox services", safety: .caution)),
        ("homebrew.mxcl", ServiceInfo(summary: "Homebrew-managed service", safety: .caution)),
        ("com.logitech", ServiceInfo(summary: "Logitech device software", safety: .caution)),
        ("com.teamviewer", ServiceInfo(summary: "TeamViewer remote access", safety: .caution)),
        ("com.microsoft.OneDrive", ServiceInfo(summary: "OneDrive file sync", safety: .caution)),
        ("com.microsoft.autoupdate", ServiceInfo(summary: "Microsoft AutoUpdate", safety: .safe)),
        ("com.google.Chrome", ServiceInfo(summary: "Chrome background helper", safety: .safe)),
        ("com.brave", ServiceInfo(summary: "Brave browser updater", safety: .safe)),
        ("org.mozilla", ServiceInfo(summary: "Firefox background updater", safety: .safe)),
        ("com.skype", ServiceInfo(summary: "Skype helper", safety: .safe)),
        ("com.slack", ServiceInfo(summary: "Slack helper", safety: .safe)),
        ("com.tinyspeck", ServiceInfo(summary: "Slack helper", safety: .safe)),
        ("com.discord", ServiceInfo(summary: "Discord updater", safety: .safe)),
        ("com.parallels", ServiceInfo(summary: "Parallels Desktop services", safety: .caution)),
        ("com.vmware", ServiceInfo(summary: "VMware Fusion services", safety: .caution)),
        ("com.macpaw", ServiceInfo(summary: "MacPaw (CleanMyMac) background agent", safety: .caution)),
        ("com.malwarebytes", ServiceInfo(summary: "Malwarebytes protection", safety: .caution)),
        ("com.eset", ServiceInfo(summary: "ESET security services", safety: .caution)),
        ("com.symantec", ServiceInfo(summary: "Symantec / Norton security services", safety: .caution)),
        ("com.nordvpn", ServiceInfo(summary: "NordVPN background service", safety: .caution)),
        ("com.expressvpn", ServiceInfo(summary: "ExpressVPN background service", safety: .caution)),
        ("com.wacom", ServiceInfo(summary: "Wacom tablet driver", safety: .caution)),
        ("com.elgato", ServiceInfo(summary: "Elgato device software", safety: .caution)),
        ("com.canon", ServiceInfo(summary: "Canon printer utilities", safety: .safe)),
        ("com.epson", ServiceInfo(summary: "Epson printer utilities", safety: .safe)),
        ("com.hp", ServiceInfo(summary: "HP printer utilities", safety: .safe)),
        ("com.jetbrains", ServiceInfo(summary: "JetBrains toolbox helper", safety: .safe)),
        ("com.citrix", ServiceInfo(summary: "Citrix Workspace services", safety: .caution)),
        ("com.cisco", ServiceInfo(summary: "Cisco VPN / security client", safety: .caution)),
        ("com.apple.", ServiceInfo(summary: "macOS system service", safety: .system))
    ]

    public static func info(for label: String) -> ServiceInfo? {
        table.first { label.hasPrefix($0.prefix) }?.info
    }
}

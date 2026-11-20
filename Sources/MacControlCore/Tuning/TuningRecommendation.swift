//
//  TuningRecommendation.swift
//  MacControlCore
//

import Foundation

public enum TuningRisk: Int, Equatable {
    case low, medium
}

public enum TuningRestart: Equatable {
    case none
    case dock
}

/// A visual or behavioral setting that can make an older Mac feel faster.
public struct TuningRecommendation: Identifiable, Equatable {

    public enum ValueKind: Equatable { case bool, string }

    public let id: String
    /// English texts, used as localization keys.
    public let title: String
    public let effect: String
    public let risk: TuningRisk
    /// `defaults` domain and key.
    public let domain: String
    public let key: String
    public let kind: ValueKind
    /// Value that makes the Mac faster ("1"/"0" for booleans).
    public let desiredValue: String
    public let restart: TuningRestart
    /// Settings in `com.apple.universalaccess` may be refused without Accessibility permission.
    public let mayNeedPermission: Bool
    /// macOS protects this setting from command-line changes (it needs Full Disk Access even for the same value),
    /// so the user turns it on in System Settings; the app only reads its state.
    public var requiresSystemSettings = false

    /// The built-in catalog.
    public static let all: [TuningRecommendation] = [
        TuningRecommendation(id: "reduceTransparency", title: "Reduce transparency",
                             effect: "Less GPU work for menus, sidebars and the Dock. Noticeable on older graphics.",
                             risk: .low, domain: "com.apple.universalaccess", key: "reduceTransparency",
                             kind: .bool, desiredValue: "1", restart: .none, mayNeedPermission: true,
                             requiresSystemSettings: true),
        TuningRecommendation(id: "reduceMotion", title: "Reduce motion",
                             effect: "Replaces slide and zoom animations with simple fades.",
                             risk: .low, domain: "com.apple.universalaccess", key: "reduceMotion",
                             kind: .bool, desiredValue: "1", restart: .none, mayNeedPermission: true,
                             requiresSystemSettings: true),
        TuningRecommendation(id: "windowAnimations", title: "Turn off window animations",
                             effect: "Windows open and close instantly.",
                             risk: .low, domain: "NSGlobalDomain", key: "NSAutomaticWindowAnimationsEnabled",
                             kind: .bool, desiredValue: "0", restart: .none, mayNeedPermission: false),
        TuningRecommendation(id: "dockMagnification", title: "Turn off Dock magnification",
                             effect: "Removes the zoom effect when moving over the Dock.",
                             risk: .low, domain: "com.apple.dock", key: "magnification",
                             kind: .bool, desiredValue: "0", restart: .dock, mayNeedPermission: false),
        TuningRecommendation(id: "minimizeEffect", title: "Use the simple minimize effect",
                             effect: "Windows shrink instead of using the genie effect.",
                             risk: .low, domain: "com.apple.dock", key: "mineffect",
                             kind: .string, desiredValue: "scale", restart: .dock, mayNeedPermission: false),
        TuningRecommendation(id: "launchAnimation", title: "Turn off app launch animation",
                             effect: "Dock icons no longer bounce while an app opens.",
                             risk: .low, domain: "com.apple.dock", key: "launchanim",
                             kind: .bool, desiredValue: "0", restart: .dock, mayNeedPermission: false)
    ]
}

/// Setting the user has already changed, kept so "Restore" can put it back.
struct OriginalValue: Codable, Equatable {
    /// `false` when the key did not exist (macOS default), so restoring deletes it.
    let wasPresent: Bool
    let value: String?
}

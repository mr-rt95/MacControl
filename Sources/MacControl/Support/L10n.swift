//
//  L10n.swift
//  MacControl
//

import Foundation

/// Localized strings for places where SwiftUI's `LocalizedStringKey` cannot be used
/// (values passed as plain `String`). Keys are the English texts.
func tr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string, e.g. `tr("of %@", total)`.
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}

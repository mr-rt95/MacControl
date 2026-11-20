//
//  ActionPreview.swift
//  MacControl
//

import Foundation
import MacControlCore

/// One line in the confirmation list.
struct PreviewItem: Identifiable {
    let path: String
    let bytes: UInt64
    var id: String { path }
}

/// Exactly what an action will do, shown to the user before anything happens.
/// Every file-changing operation in the app goes through one of these.
struct ActionPreview: Identifiable {
    let id = UUID()
    let title: String
    var message: String?
    let items: [PreviewItem]
    var warnings: [String] = []
    /// When set, the user must tick this statement before the confirm button works.
    var acknowledgement: String?
    let confirmTitle: String
    let perform: () -> Void

    var totalBytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }
}

/// A short result message shown at the top of a screen after an action.
struct Banner: Identifiable {
    let id = UUID()
    let message: String
    var isError = false
    /// When set, the banner offers to undo the operation.
    var undoRecordID: UUID?
}

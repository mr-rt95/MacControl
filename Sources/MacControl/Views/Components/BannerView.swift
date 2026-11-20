//
//  BannerView.swift
//  MacControl
//

import SwiftUI

/// Result message shown after an action, with an optional Undo button.
struct BannerView: View {

    let banner: Banner
    var onUndo: ((UUID) -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(banner.isError ? Palette.warning : Palette.good)
            Text(verbatim: banner.message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let id = banner.undoRecordID, let onUndo = onUndo {
                Button("Undo") { onUndo(id) }
            }
            Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.cardBackground))
    }
}

extension View {
    /// Shows a banner above the content when one is set.
    func banner(_ banner: Binding<Banner?>, onUndo: ((UUID) -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let value = banner.wrappedValue {
                BannerView(banner: value, onUndo: onUndo) { banner.wrappedValue = nil }
            }
            self
        }
    }
}

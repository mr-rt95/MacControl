//
//  ConfirmationSheet.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Shows exactly what is about to happen (every file and the total size) and asks for confirmation.
struct ConfirmationSheet: View {

    let preview: ActionPreview
    let dismiss: () -> Void

    @State private var acknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: preview.title).font(.title2.weight(.semibold))
            if let message = preview.message {
                Text(verbatim: message).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(verbatim: tr("%@ items", "\(preview.items.count)"))
                if preview.totalBytes > 0 { Text(verbatim: "· " + Formatters.bytes(preview.totalBytes)).monospacedDigit() }
            }
            .font(.headline)

            List(preview.items) { item in
                HStack {
                    Text(verbatim: item.path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if item.bytes > 0 {
                        Text(verbatim: Formatters.bytes(item.bytes)).monospacedDigit().foregroundColor(.secondary)
                    }
                }
                .font(.system(.callout, design: .monospaced))
            }
            .frame(minHeight: 160, maxHeight: 300)

            ForEach(preview.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let text = preview.acknowledgement {
                Toggle(text, isOn: $acknowledged)
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button(preview.confirmTitle) {
                    dismiss()
                    preview.perform()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.acknowledgement != nil && !acknowledged)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

extension View {
    /// Presents the confirmation sheet for an optional preview.
    func confirmation(_ preview: Binding<ActionPreview?>) -> some View {
        sheet(item: preview) { item in
            ConfirmationSheet(preview: item) { preview.wrappedValue = nil }
        }
    }
}

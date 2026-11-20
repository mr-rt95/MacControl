//
//  ReportView.swift
//  MacControl
//

import SwiftUI
import WebKit
import MacControlCore

/// Previews the status report and lets the user save or copy it. Nothing is sent anywhere.
struct ReportView: View {

    @ObservedObject var model: ReportViewModel
    @ObservedObject var monitoring: MonitoringService
    @ObservedObject var startup: StartupViewModel
    let groups: [ProcessGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A summary you can send to a repair shop or support. It contains hardware facts, load figures and app names, but no personal file names or document contents.")
                .foregroundColor(.secondary)

            HStack {
                Picker("", selection: $model.format) {
                    Text("Markdown").tag(ReportViewModel.Format.markdown)
                    Text("HTML").tag(ReportViewModel.Format.html)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 220)
                Button("Refresh") { regenerate() }
                Spacer()
                Button("Copy") { model.copy() }
                Button("Save…") { model.save() }.keyboardShortcut(.defaultAction)
            }

            preview
                .frame(minHeight: 420)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
        }
        .banner($model.banner)
        .onAppear {
            startup.refresh(groups: groups)
            regenerate()
        }
        .onChange(of: model.format) { _ in regenerate() }
    }

    @ViewBuilder
    private var preview: some View {
        if model.format == .html {
            HTMLPreview(html: model.text)
        } else {
            ScrollView {
                Text(verbatim: model.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    private func regenerate() {
        model.generate(monitoring: monitoring, startupItems: startup.items)
    }
}

/// Renders HTML without network access or scripts.
private struct HTMLPreview: NSViewRepresentable {

    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: nil)
    }
}

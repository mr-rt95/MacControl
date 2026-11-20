//
//  PermissionsView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Everything MacControl may ask macOS for, with the current state and a shortcut to the right System Settings pane.
struct PermissionsView: View {

    @ObservedObject var model: PermissionsViewModel
    @ObservedObject var helper: HelperManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MacControl only asks for what a feature needs. Nothing is requested until you use that feature or press a button here.")
                .foregroundColor(.secondary)

            helperCard

            ForEach(model.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    statusIcon(item.status)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: item.title).font(.headline)
                            Text(Self.statusText(item.status)).font(.caption).foregroundColor(Self.color(item.status))
                        }
                        Text(verbatim: item.usedFor).font(.callout).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(item.actions) { action in Button(action.title, action: action.perform) }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
            }
        }
        .onAppear {
            model.refresh()
            helper.refresh()
        }
    }

    // MARK: - Administrator helper

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "key.fill").foregroundColor(helper.isUsable ? Palette.good : .secondary)
                Text("Administrator helper").font(.headline)
                Text(helperStatusText).font(.caption).foregroundColor(helper.isUsable ? Palette.good : Palette.warning)
                Spacer()
                helperButtons
            }
            Text("A small background service that runs as administrator, only for actions you confirm: removing system-wide leftovers of deleted apps, deleting Time Machine snapshots, switching system launch daemons, quitting other users' processes, and showing root processes and CPU frequency. It accepts requests only from this app, refuses protected system items, and never runs arbitrary commands.")
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if helper.status == .unsigned {
                Label("This build is not signed with a certificate, so the helper cannot be installed. A free self-signed certificate is enough; see docs/HELPER.md.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundColor(Palette.warning).fixedSize(horizontal: false, vertical: true)
            }
            if helper.status == .requiresApproval {
                Text("Allow MacControl in System Settings ▸ General ▸ Login Items & Extensions, then come back.")
                    .font(.callout).foregroundColor(Palette.warning)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    @ViewBuilder
    private var helperButtons: some View {
        switch helper.status {
        case .notRegistered, .failed:
            Button("Install helper") { helper.install() }
        case .requiresApproval:
            Button("Open Login Items settings") { helper.openApprovalSettings() }
        case .enabled:
            Button("Remove helper") { helper.uninstall() }
        case .unsigned, .unsupportedOS:
            EmptyView()
        }
    }

    private var helperStatusText: String {
        switch helper.status {
        case .unsigned:         return tr("Unavailable in this build")
        case .unsupportedOS:    return tr("Needs macOS 13 or newer")
        case .notRegistered:    return tr("Not installed")
        case .requiresApproval: return tr("Waiting for approval")
        case .enabled:          return helper.isReachable ? tr("Active") : tr("Installed, not responding")
        case .failed(let text): return tr("Error: %@", text)
        }
    }

    // MARK: - Helpers

    private func statusIcon(_ status: PermissionStatus) -> some View {
        let symbol: String
        switch status {
        case .granted:       symbol = "checkmark.circle.fill"
        case .denied:        symbol = "xmark.circle.fill"
        case .notDetermined: symbol = "questionmark.circle.fill"
        case .unknown:       symbol = "circle.dashed"
        }
        return Image(systemName: symbol).font(.title3).foregroundColor(Self.color(status))
    }

    static func color(_ status: PermissionStatus) -> Color {
        switch status {
        case .granted: return Palette.good
        case .denied: return Palette.critical
        case .notDetermined: return Palette.warning
        case .unknown: return .secondary
        }
    }

    static func statusText(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: return tr("Granted")
        case .denied: return tr("Not granted")
        case .notDetermined: return tr("Not asked yet")
        case .unknown: return tr("Cannot be checked")
        }
    }
}

/// Reads CPU frequency and thermal data from `powermetrics` through the helper.
struct ExtendedCPUCard: View {

    @ObservedObject var helper: HelperManager
    @State private var metrics: PowerMetrics?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Extended CPU data").font(.headline)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Read now") { read() }.disabled(!helper.isUsable || isLoading)
            }
            if !helper.isUsable {
                Text("Needs the administrator helper (Permissions).").font(.callout).foregroundColor(.secondary)
            } else if failed {
                Text("The data could not be read.").font(.callout).foregroundColor(Palette.warning)
            } else if let metrics = metrics {
                metricsRows(metrics)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    @ViewBuilder
    private func metricsRows(_ m: PowerMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let mhz = m.averageMHz {
                let nominal = m.fractionOfNominal.map { " (" + tr("%@ of nominal", Formatters.percent($0)) + ")" } ?? ""
                row(tr("Average frequency"), "\(Int(mhz)) MHz" + nominal)
            }
            if !m.coreMHz.isEmpty {
                row(tr("Per core"), m.coreMHz.map { "\(Int($0))" }.joined(separator: " · ") + " MHz")
            }
            if let watts = m.packageWatts { row(tr("Package power"), String(format: "%.1f W", watts)) }
            if let pressure = m.thermalPressure { row(tr("Thermal pressure"), tr(pressure)) }
            if m.averageMHz == nil && m.packageWatts == nil && m.thermalPressure == nil {
                Text("No data").foregroundColor(.secondary)
            }
        }
        .font(.callout)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title).foregroundColor(.secondary)
            Spacer()
            Text(verbatim: value).monospacedDigit()
        }
    }

    private func read() {
        guard let client = helper.commandClient() else { return }
        isLoading = true
        failed = false
        DispatchQueue.global(qos: .userInitiated).async {
            let result = client.powerMetrics()
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let value): metrics = PowerMetrics.parse(value)
                case .failure: failed = true
                }
            }
        }
    }
}

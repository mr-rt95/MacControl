//
//  AppsView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Installed applications; removes an app together with its leftovers.
struct AppsView: View {

    @ObservedObject var model: AppsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Sort by", selection: $model.sort) {
                    Text("Size").tag(AppsViewModel.Sort.size)
                    Text("Last used").tag(AppsViewModel.Sort.lastUsed)
                    Text("Name").tag(AppsViewModel.Sort.name)
                }
                .pickerStyle(.segmented).frame(maxWidth: 300)
                Toggle("Not used for 6 months", isOn: $model.showOnlyUnused)
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
                else { Button("Rescan") { model.scan() } }
            }

            // The app list scrolls by itself; the details panel stays in place beside it.
            HStack(alignment: .top, spacing: 14) {
                ScrollView { list }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView { detail }
                    .frame(width: 330)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .banner($model.banner, onUndo: { model.undo($0) })
        .confirmation($model.preview)
        .onAppear { if model.apps.isEmpty { model.scan() } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(model.visibleApps) { app in
                Button { model.select(app) } label: {
                    HStack {
                        if !app.isRemovable { Image(systemName: "lock.fill").foregroundColor(.secondary).font(.caption) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: app.name)
                            Text(verbatim: lastUsedText(app)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(verbatim: Formatters.bytes(app.bytes)).monospacedDigit().foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(model.selected == app ? Color.accentColor.opacity(0.18) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
            if model.visibleApps.isEmpty && !model.isScanning {
                Text("No apps to show.").foregroundColor(.secondary).padding()
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let app = model.selected {
                Text(verbatim: app.name).font(.title3.weight(.semibold))
                if let version = app.version { Text(verbatim: tr("Version %@", version)).font(.caption).foregroundColor(.secondary) }
                Text(verbatim: app.bundleIdentifier ?? "").font(.caption).foregroundColor(.secondary)

                if !app.isRemovable {
                    Label("Apple's built-in apps are protected and cannot be removed.", systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                } else if model.isPlanning {
                    HStack { ProgressView().controlSize(.small); Text("Looking for leftover files…").foregroundColor(.secondary) }
                } else if let plan = model.plan {
                    leftoverSection(plan)
                }
            } else {
                Text("Select an app to see what removing it would delete.").foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    private func leftoverSection(_ plan: UninstallPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: tr("%@ related items", "\(plan.leftovers.count)")).font(.headline)
            ForEach(plan.leftovers) { leftover in
                Toggle(isOn: Binding(
                    get: { model.keptLeftovers.contains(leftover.url) },
                    set: { on in if on { model.keptLeftovers.insert(leftover.url) } else { model.keptLeftovers.remove(leftover.url) } }
                )) {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: leftover.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text(verbatim: leftover.url.deletingLastPathComponent().path).font(.caption2).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Text(verbatim: Formatters.bytes(leftover.bytes)).font(.caption).monospacedDigit()
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(leftover.requiresAdministrator && !model.helperUsable)
                .help(leftover.requiresAdministrator ? tr("Needs administrator rights") : "")
            }
            Button("Remove…") { model.requestUninstall() }.keyboardShortcut(.defaultAction)
        }
    }

    private func lastUsedText(_ app: InstalledApp) -> String {
        guard let date = app.lastUsed else { return tr("Last used: unknown") }
        return tr("Last used: %@", date.formatted(date: .abbreviated, time: .omitted))
    }
}

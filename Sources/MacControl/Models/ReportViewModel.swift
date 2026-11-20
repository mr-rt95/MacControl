//
//  ReportViewModel.swift
//  MacControl
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import MacControlCore

/// Builds, previews and saves the Mac status report.
final class ReportViewModel: ObservableObject {

    enum Format: String, CaseIterable { case markdown, html }

    @Published var format = Format.markdown
    @Published private(set) var text = ""
    @Published var banner: Banner?

    private let formatter = ReportFormatter(localize: { tr($0) })

    /// Collects the current data and renders it in the selected format.
    func generate(monitoring: MonitoringService, startupItems: [LaunchItem]) {
        guard let snapshot = monitoring.snapshot else { return }
        let analysis = monitoring.analysis

        var report = SystemReport()
        report.collectSystemFacts()
        report.memory = snapshot.memory
        report.disk = snapshot.disk
        report.diskHealth = analysis.diskHealth
        report.battery = analysis.battery
        report.throttle = analysis.throttle
        report.temperatures = snapshot.temperatures
        report.fans = snapshot.fans
        report.topProcesses = SystemReport.processes(from: snapshot.processGroups)
        report.startupItems = startupItems.filter { !$0.isApple && ($0.runsAtLoad || $0.keepsAlive) }.map(\.label)
        let dayAgo = Date().addingTimeInterval(-86_400)
        report.recentEvents = monitoring.events.filter { $0.isOngoing || ($0.end ?? $0.start) >= dayAgo }
        report.findings = analysis.findings.map { finding in
            let words = FindingPresenter.text(for: finding)
            return ReportFinding(severity: finding.severity, title: words.title, detail: words.detail,
                                 advice: words.advice, evidence: finding.evidence)
        }
        text = format == .html ? formatter.html(report) : formatter.markdown(report)
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        banner = Banner(message: tr("Report copied to the clipboard."))
    }

    /// Saves where the user chooses; nothing is sent anywhere.
    func save() {
        let panel = NSSavePanel()
        let isHTML = format == .html
        panel.nameFieldStringValue = "MacControl-report." + (isHTML ? "html" : "md")
        panel.allowedContentTypes = [isHTML ? .html : (UTType(filenameExtension: "md") ?? .plainText)]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            banner = Banner(message: tr("Report saved."))
        } catch {
            banner = Banner(message: tr("The report could not be saved."), isError: true)
        }
    }
}

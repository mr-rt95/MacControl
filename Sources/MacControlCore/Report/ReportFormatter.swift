//
//  ReportFormatter.swift
//  MacControlCore
//

import Foundation

/// Renders a `SystemReport` as Markdown or HTML.
///
/// Labels are English keys passed through `localize`, so the report follows the app language.
public struct ReportFormatter {

    private let localize: (String) -> String

    public init(localize: @escaping (String) -> String = { $0 }) {
        self.localize = localize
    }

    // MARK: - Content model shared by both formats

    private struct Section {
        let title: String
        let rows: [(String, String)]
        let bullets: [String]
    }

    private func sections(for report: SystemReport) -> [Section] {
        let t = localize
        var result: [Section] = []

        result.append(Section(title: t("System information"), rows: [
            (t("Model"), report.modelIdentifier.isEmpty ? t("No data") : report.modelIdentifier),
            ("macOS", report.osVersion),
            (t("Processor cores"), "\(report.logicalCores)"),
            (t("Memory installed"), bytes(report.memory.total)),
            (t("Uptime"), duration(report.uptime))
        ], bullets: []))

        let diagnosis: [String] = report.findings.isEmpty
            ? [t("Everything is fine")]
            : report.findings.map { finding in
                var line = "\(finding.title). \(finding.detail) \(finding.advice)"
                if !finding.evidence.isEmpty {
                    line += " [" + finding.evidence.map { "\(t($0.label)): \(t($0.value))" }.joined(separator: "; ") + "]"
                }
                return line
            }
        result.append(Section(title: t("Diagnosis"), rows: [], bullets: diagnosis))

        let memory = report.memory
        result.append(Section(title: t("Memory"), rows: [
            (t("Used"), "\(bytes(memory.used)) / \(bytes(memory.total))"),
            (t("App memory"), bytes(memory.app)), (t("Wired"), bytes(memory.wired)),
            (t("Compressed"), bytes(memory.compressed)),
            (t("Swap"), "\(bytes(memory.swapUsed)) / \(bytes(memory.swapTotal))"),
            (t("Memory pressure"), t("\(memory.pressure)".lowercased()))
        ], bullets: []))

        var diskRows = [(t("Free space"), "\(bytes(report.disk.availableBytes)) / \(bytes(report.disk.totalBytes))"),
                        (t("SMART status"), smart(report.diskHealth.smart))]
        if let name = report.diskHealth.mediaName { diskRows.append((t("Model"), name)) }
        if let wear = report.diskHealth.wear {
            diskRows.append((t("Life used"), "\(wear.percentageUsed)%"))
            diskRows.append((t("Spare blocks"), "\(wear.availableSpare)%"))
            diskRows.append((t("Data written"), ByteCountFormatter.string(fromByteCount: Int64(clamping: wear.bytesWritten), countStyle: .decimal)))
            diskRows.append((t("Media errors"), "\(wear.mediaErrors)"))
        }
        result.append(Section(title: t("Disk"), rows: diskRows, bullets: []))

        if let battery = report.battery {
            result.append(Section(title: t("Battery"), rows: [
                (t("Capacity vs. new"), "\(percent(battery.healthFraction)) (\(battery.maximumCapacity) / \(battery.designCapacity) mAh)"),
                (t("Charge cycles"), "\(battery.cycleCount)"),
                (t("Temperature"), battery.temperatureCelsius.map { String(format: "%.0f °C", $0) } ?? t("No data"))
            ], bullets: []))
        }

        var thermalRows = report.temperatures.map { reading in
            (t(reading.sensor.title), reading.celsius.map { String(format: "%.0f °C", $0) } ?? t("No data"))
        }
        thermalRows.append((t("Speed limit"), report.throttle.speedLimitPercent.map { "\($0)%" } ?? t("No data")))
        thermalRows.append((t("Thermal state"), t("\(report.throttle.thermalState)".lowercased())))
        for fan in report.fans {
            thermalRows.append(("\(t("Fan")) \(fan.index + 1)", fan.currentRPM.map { String(format: t("%@ rpm"), String(format: "%.0f", $0)) } ?? t("No data")))
        }
        result.append(Section(title: t("Temperatures & fans"), rows: thermalRows, bullets: []))

        result.append(Section(title: t("Top consumers"), rows: [], bullets: report.topProcesses.map {
            String(format: "%@ — %.0f%% CPU, %@", $0.name, $0.cpuPercent, bytes($0.memoryBytes))
        }))

        result.append(Section(title: t("Startup items"), rows: [],
                              bullets: report.startupItems.isEmpty ? [t("Nothing starts automatically.")] : report.startupItems))

        result.append(Section(title: t("Events in the last 24 hours"), rows: [],
                              bullets: report.recentEvents.isEmpty ? [t("Nothing has slowed this Mac down recently.")]
                                  : report.recentEvents.map(eventLine)))
        return result
    }

    // MARK: - Markdown

    public func markdown(_ report: SystemReport) -> String {
        var out = "# \(localize("Mac status report"))\n\n"
        out += "_\(dateString(report.generated))_\n"
        for section in sections(for: report) {
            out += "\n## \(section.title)\n\n"
            for (label, value) in section.rows { out += "- **\(label):** \(value)\n" }
            for bullet in section.bullets { out += "- \(bullet)\n" }
        }
        out += "\n---\n_\(localize("The report contains no personal file names or document contents. Sending it is up to you."))_\n"
        return out
    }

    // MARK: - HTML

    public func html(_ report: SystemReport) -> String {
        let title = Self.escape(localize("Mac status report"))
        var out = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(title)</title>
        <style>
        body{font-family:-apple-system,Helvetica,sans-serif;max-width:760px;margin:2em auto;padding:0 1em;color:#222}
        h1{font-size:1.6em} h2{font-size:1.15em;border-bottom:1px solid #ddd;padding-bottom:.2em;margin-top:1.6em}
        table{border-collapse:collapse;width:100%} td{padding:.2em .6em .2em 0;vertical-align:top} td:first-child{color:#666;width:42%}
        ul{padding-left:1.2em} .note{color:#888;font-size:.85em;margin-top:2em}
        </style></head><body>
        <h1>\(title)</h1><p>\(Self.escape(dateString(report.generated)))</p>

        """
        for section in sections(for: report) {
            out += "<h2>\(Self.escape(section.title))</h2>\n"
            if !section.rows.isEmpty {
                out += "<table>" + section.rows.map { "<tr><td>\(Self.escape($0.0))</td><td>\(Self.escape($0.1))</td></tr>" }.joined() + "</table>\n"
            }
            if !section.bullets.isEmpty {
                out += "<ul>" + section.bullets.map { "<li>\(Self.escape($0))</li>" }.joined() + "</ul>\n"
            }
        }
        out += "<p class=\"note\">\(Self.escape(localize("The report contains no personal file names or document contents. Sending it is up to you.")))</p>\n</body></html>\n"
        return out
    }

    /// Escapes text for HTML so process or sensor names cannot inject markup.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Formatting helpers

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private func percent(_ fraction: Double) -> String { String(format: "%.0f%%", fraction * 100) }

    private func duration(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400, hours = Int(seconds) % 86_400 / 3_600, minutes = Int(seconds) % 3_600 / 60
        return days > 0 ? String(format: localize("%@ d %@ h"), "\(days)", "\(hours)")
                        : String(format: localize("%@ h %@ min"), "\(hours)", "\(minutes)")
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func smart(_ status: SMARTStatus) -> String {
        switch status {
        case .verified: return localize("Verified")
        case .failing: return localize("Failing")
        case .notSupported: return localize("Not supported")
        case .unknown: return localize("No data")
        }
    }

    private func eventLine(_ event: LoggedEvent) -> String {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let range = event.end.map { "\(time.string(from: event.start))–\(time.string(from: $0))" } ?? time.string(from: event.start)
        var parts = ["\(range) \(localize(Self.title(of: event.kind)))", String(format: localize("CPU %@"), String(format: "%.0f%%", event.peakCPU * 100))]
        if let temperature = event.peakTemperature { parts.append(String(format: "%.0f °C", temperature)) }
        if !event.topProcesses.isEmpty { parts.append(event.topProcesses.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }

    /// English title (localization key) of an event kind.
    public static func title(of kind: EventKind) -> String {
        switch kind {
        case .cpuLoad:        return "High processor load"
        case .overheating:    return "Overheating"
        case .memoryPressure: return "Critical memory pressure"
        case .swapGrowth:     return "Swap growth"
        case .diskAlmostFull: return "Disk almost full"
        case .throttling:     return "CPU throttling"
        }
    }
}

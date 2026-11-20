//
//  HealthView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// SSD and battery condition.
struct HealthView: View {

    let snapshot: SystemSnapshot
    let analysis: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ssdCard
            batteryCard
        }
    }

    // MARK: - SSD

    private var ssdCard: some View {
        let health = analysis.diskHealth
        return card("Drive") {
            row("SMART status", smartText(health.smart), color: smartColor(health.smart))
            if let name = health.mediaName { row("Model", name) }
            row("Free space", "\(Formatters.bytes(snapshot.disk.availableBytes)) / \(Formatters.bytes(snapshot.disk.totalBytes))")
            ProgressBar(fraction: snapshot.disk.usedFraction, color: Palette.color(forLoad: snapshot.disk.usedFraction))
            if let wear = health.wear { wearRows(wear) }
            if health.wear == nil && (health.smart == .notSupported || health.smart == .unknown || health.smart == .verified) {
                Text("This drive does not provide detailed wear data; only the overall status is shown.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    /// NVMe SMART counters, when the drive provides them.
    @ViewBuilder
    private func wearRows(_ wear: SSDWear) -> some View {
        Group {
            row("Life used", "\(wear.percentageUsed)%", color: Palette.color(forLoad: Double(wear.percentageUsed) / 100))
            ProgressBar(fraction: Double(min(wear.percentageUsed, 100)) / 100, color: Palette.color(forLoad: Double(wear.percentageUsed) / 100))
            row("Spare blocks", "\(wear.availableSpare)%")
            row("Data written", Formatters.bytes(wear.bytesWritten))
            row("Data read", Formatters.bytes(wear.bytesRead))
        }
        Group {
            row("Power-on time", tr("%@ h", "\(wear.powerOnHours)"))
            row("Power cycles", "\(wear.powerCycles)")
            row("Unsafe shutdowns", "\(wear.unsafeShutdowns)")
            row("Media errors", "\(wear.mediaErrors)", color: wear.mediaErrors > 0 ? Palette.warning : .primary)
            if let t = wear.temperatureCelsius { row("Temperature", Formatters.temperature(t)) }
        }
        Text("Wear is the manufacturer's own estimate; it is not a prediction of when the drive will fail.")
            .font(.caption).foregroundColor(.secondary)
    }

    private func smartText(_ status: SMARTStatus) -> String {
        switch status {
        case .verified:     return tr("Verified")
        case .failing:      return tr("Failing")
        case .notSupported: return tr("Not supported")
        case .unknown:      return tr("No data")
        }
    }

    private func smartColor(_ status: SMARTStatus) -> Color {
        switch status {
        case .verified: return Palette.good
        case .failing:  return Palette.critical
        default:        return .secondary
        }
    }

    // MARK: - Battery

    @ViewBuilder
    private var batteryCard: some View {
        if let battery = analysis.battery {
            card("Battery") {
                row("Capacity vs. new", "\(Formatters.percent(battery.healthFraction))  (\(battery.maximumCapacity) / \(battery.designCapacity) mAh)",
                    color: Palette.color(forLoad: battery.wearFraction * 1.5))
                ProgressBar(fraction: battery.healthFraction, color: Palette.color(forLoad: battery.wearFraction * 1.5))
                row("Charge cycles", "\(battery.cycleCount)")
                row("Charge", Formatters.percent(battery.chargeFraction))
                if let t = battery.temperatureCelsius { row("Temperature", Formatters.temperature(t)) }
                row("Power", battery.isCharging ? tr("Charging") : (battery.isPluggedIn ? tr("Plugged in") : tr("On battery")))
                if battery.wearFraction >= 0.2 {
                    Label("Consider replacing the battery.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(Palette.warning)
                }
            }
        } else {
            card("Battery") { Text("This Mac has no battery.").foregroundColor(.secondary) }
        }
    }

    // MARK: - Layout helpers

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    private func row(_ title: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(verbatim: tr(title)).foregroundColor(.secondary)
            Spacer()
            Text(verbatim: value).monospacedDigit().foregroundColor(color)
        }
        .font(.callout)
    }
}

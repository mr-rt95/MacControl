//
//  SensorsView.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Temperatures grouped by component and fan speeds. Missing data is stated honestly.
struct SensorsView: View {

    let snapshot: SystemSnapshot
    let modelIdentifier: String
    let sensorsAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: modelIdentifier).foregroundColor(.secondary)
                Spacer()
            }

            if !sensorsAvailable {
                Label("Sensors are not available on this Mac.", systemImage: "questionmark.circle")
                    .foregroundColor(.secondary)
            }

            ForEach(SensorCategory.allCases, id: \.self) { category in
                categorySection(category)
            }

            fansSection
        }
    }

    // MARK: - Temperatures

    private func categorySection(_ category: SensorCategory) -> some View {
        let readings = snapshot.temperatures.filter { $0.sensor.category == category }
        return VStack(alignment: .leading, spacing: 8) {
            Text(category.title).font(.headline)
            if readings.isEmpty {
                Text("No data").foregroundColor(.secondary)
            } else {
                ForEach(readings) { reading in
                    temperatureRow(reading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }

    private func temperatureRow(_ reading: TemperatureReading) -> some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(reading.sensor.title))
                .frame(width: 200, alignment: .leading)
            if let celsius = reading.celsius {
                let level = ThermalLevel.classify(celsius: celsius, category: reading.sensor.category)
                ProgressBar(fraction: celsius / 110, color: Palette.color(for: level), height: 6)
                Text(verbatim: Formatters.temperature(celsius))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
                    .foregroundColor(Palette.color(for: level))
                Text(level.title)
                    .font(.caption).foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
            } else {
                Text("No data").foregroundColor(.secondary)
                Spacer()
            }
        }
        .font(.callout)
    }

    // MARK: - Fans

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fans").font(.headline)
            if snapshot.fans.isEmpty {
                Text("No data").foregroundColor(.secondary)
            } else {
                ForEach(snapshot.fans) { fan in
                    HStack(spacing: 10) {
                        Text(verbatim: "#\(fan.index + 1)").frame(width: 200, alignment: .leading)
                        if let current = fan.currentRPM {
                            ProgressBar(fraction: fan.speedFraction ?? 0, color: .teal, height: 6)
                            Text(verbatim: tr("%@ rpm", Formatters.rpm(current)))
                                .monospacedDigit()
                                .frame(width: 100, alignment: .trailing)
                            Text(verbatim: "\(fan.minimumRPM.map(Formatters.rpm) ?? "—") – \(fan.maximumRPM.map(Formatters.rpm) ?? "—")")
                                .font(.caption).foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                        } else {
                            Text("No data").foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cardBackground))
    }
}

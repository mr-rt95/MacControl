//
//  Formatters.swift
//  MacControl
//

import Foundation

/// Shared number formatting for all screens. Formatters are created once because they are expensive.
enum Formatters {

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    /// "6.7 GB"
    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(clamping: value))
    }

    /// "1.2 MB/s"
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = Int64(max(0, min(bytesPerSecond, Double(Int64.max / 2))))
        return byteFormatter.string(fromByteCount: value) + "/s"
    }

    /// Fraction `0...1` → "45%".
    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", max(0, fraction) * 100)
    }

    /// Process CPU usage already expressed in percent (may exceed 100) → "12.5%".
    static func cpuPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// "72 °C"
    static func temperature(_ celsius: Double) -> String {
        String(format: "%.0f °C", celsius)
    }

    /// "4596 rpm" — the unit is localized by the caller when needed.
    static func rpm(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

//
//  Palette.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Status colors shared by all screens, so "good / warm / bad" always looks the same.
enum Palette {

    static let good = Color.green
    static let warning = Color.orange
    static let critical = Color.red

    static func color(for level: ThermalLevel) -> Color {
        switch level {
        case .normal: return good
        case .warm:   return warning
        case .hot:    return critical
        }
    }

    static func color(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal:   return good
        case .warning:  return warning
        case .critical: return critical
        }
    }

    /// Color for a load/usage fraction `0...1`.
    static func color(forLoad fraction: Double) -> Color {
        switch fraction {
        case ..<0.7:  return good
        case ..<0.9:  return warning
        default:      return critical
        }
    }

    static func color(for state: SystemThermalState) -> Color {
        switch state {
        case .nominal:  return good
        case .fair:     return warning
        case .serious, .critical: return critical
        }
    }

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let track = Color.primary.opacity(0.1)
}

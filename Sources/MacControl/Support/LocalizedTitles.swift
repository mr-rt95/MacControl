//
//  LocalizedTitles.swift
//  MacControl
//

import SwiftUI
import MacControlCore

/// Maps core enums to localization keys. Keys are the English text, so a missing
/// translation falls back to readable English.
extension SensorCategory {
    var title: LocalizedStringKey {
        switch self {
        case .cpu:       return "Processor"
        case .gpu:       return "Graphics"
        case .storage:   return "Storage"
        case .battery:   return "Battery"
        case .memory:    return "Memory"
        case .enclosure: return "Enclosure & ambient"
        }
    }
}

extension MemoryPressure {
    var title: LocalizedStringKey {
        switch self {
        case .normal:   return "Normal"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }
}

extension SystemThermalState {
    var title: LocalizedStringKey {
        switch self {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        }
    }
}

extension ThermalLevel {
    var title: LocalizedStringKey {
        switch self {
        case .normal: return "Normal"
        case .warm:   return "Warm"
        case .hot:    return "Overheating"
        }
    }
}

//
//  Sensors.swift
//  MacControlCore
//

import Foundation

/// Hardware component a temperature sensor belongs to.
public enum SensorCategory: String, CaseIterable, Equatable {
    case cpu
    case gpu
    case storage
    case battery
    case memory
    case enclosure
}

/// Static description of one SMC temperature sensor.
public struct SensorDescriptor: Equatable, Hashable, Identifiable {

    /// Four-character SMC key, e.g. `TC0P`.
    public let key: String
    /// Stable, English title used as a localization key, e.g. "CPU Proximity".
    public let title: String
    public let category: SensorCategory

    public var id: String { key }

    public init(key: String, title: String, category: SensorCategory) {
        self.key = key
        self.title = title
        self.category = category
    }
}

/// Temperature reported by a sensor. `celsius == nil` means the sensor has no data.
public struct TemperatureReading: Equatable, Identifiable {

    public let sensor: SensorDescriptor
    public let celsius: Double?

    public var id: String { sensor.key }

    public init(sensor: SensorDescriptor, celsius: Double?) {
        self.sensor = sensor
        self.celsius = celsius
    }
}

/// Speed of one fan. Values are `nil` when the SMC does not report them.
public struct FanReading: Equatable, Identifiable {

    public let index: Int
    public let currentRPM: Double?
    public let minimumRPM: Double?
    public let maximumRPM: Double?

    public var id: Int { index }

    public init(index: Int, currentRPM: Double?, minimumRPM: Double?, maximumRPM: Double?) {
        self.index = index
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }

    /// Position of the current speed between minimum and maximum, `0...1`.
    public var speedFraction: Double? {
        guard let current = currentRPM, let maximum = maximumRPM, maximum > 0 else { return nil }
        let minimum = minimumRPM ?? 0
        guard maximum > minimum else { return nil }
        return min(1, max(0, (current - minimum) / (maximum - minimum)))
    }
}

/// Traffic-light classification of a temperature.
public enum ThermalLevel: Int, Equatable, Comparable {
    case normal = 0
    case warm = 1
    case hot = 2

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Classifies a temperature using thresholds appropriate for the component.
    public static func classify(celsius: Double, category: SensorCategory) -> ThermalLevel {
        let (warm, hot) = thresholds(for: category)
        if celsius >= hot { return .hot }
        if celsius >= warm { return .warm }
        return .normal
    }

    /// `(warm, hot)` thresholds in °C.
    static func thresholds(for category: SensorCategory) -> (Double, Double) {
        switch category {
        case .cpu, .gpu:  return (75, 90)
        case .storage:    return (55, 70)
        case .battery:    return (40, 50)
        case .memory:     return (70, 85)
        case .enclosure:  return (45, 55)
        }
    }
}

/// Mirror of `ProcessInfo.ThermalState`, free of Foundation naming clashes.
public enum SystemThermalState: Int, Equatable, Comparable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public static func < (lhs: SystemThermalState, rhs: SystemThermalState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:  self = .nominal
        case .fair:     self = .fair
        case .serious:  self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

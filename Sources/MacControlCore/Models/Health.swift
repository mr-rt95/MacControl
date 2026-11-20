//
//  Health.swift
//  MacControlCore
//

import Foundation

/// CPU throttling state from public sources (`pmset -g therm`, `ProcessInfo.thermalState`).
public struct ThrottleInfo: Equatable {

    /// Percentage of maximum CPU speed the system currently allows (`100` = no limit).
    /// `nil` when `pmset` gave no value.
    public let speedLimitPercent: Int?
    public let thermalState: SystemThermalState

    public init(speedLimitPercent: Int?, thermalState: SystemThermalState) {
        self.speedLimitPercent = speedLimitPercent
        self.thermalState = thermalState
    }

    /// `true` when the CPU is running below its maximum speed or macOS reports serious heat.
    public var isThrottling: Bool {
        (speedLimitPercent ?? 100) < 100 || thermalState >= .serious
    }

    public static let none = ThrottleInfo(speedLimitPercent: nil, thermalState: .nominal)
}

/// Result of the SMART self-assessment of the startup drive.
public enum SMARTStatus: String, Codable, Equatable {
    case verified
    case failing
    case notSupported
    case unknown
}

/// Wear and usage counters of an NVMe SSD (from its SMART log). Available only on drives that expose them.
public struct SSDWear: Equatable {
    /// Manufacturer's estimate of the drive's life used, percent. May exceed 100.
    public let percentageUsed: Int
    /// Remaining spare blocks, percent, and the level below which the drive reports a warning.
    public let availableSpare: Int
    public let spareThreshold: Int
    /// NVMe critical-warning bit field; 0 means none.
    public let criticalWarning: Int
    public let bytesWritten: UInt64
    public let bytesRead: UInt64
    public let powerOnHours: UInt64
    public let powerCycles: UInt64
    public let unsafeShutdowns: UInt64
    public let mediaErrors: UInt64
    public let temperatureCelsius: Double?

    public init(percentageUsed: Int, availableSpare: Int, spareThreshold: Int, criticalWarning: Int,
                bytesWritten: UInt64, bytesRead: UInt64, powerOnHours: UInt64, powerCycles: UInt64,
                unsafeShutdowns: UInt64, mediaErrors: UInt64, temperatureCelsius: Double?) {
        self.percentageUsed = percentageUsed
        self.availableSpare = availableSpare
        self.spareThreshold = spareThreshold
        self.criticalWarning = criticalWarning
        self.bytesWritten = bytesWritten
        self.bytesRead = bytesRead
        self.powerOnHours = powerOnHours
        self.powerCycles = powerCycles
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.temperatureCelsius = temperatureCelsius
    }
}

public struct DiskHealth: Equatable {
    public let smart: SMARTStatus
    public let isSolidState: Bool?
    /// Model name of the drive, if known.
    public let mediaName: String?
    /// Detailed wear data, when the drive provides it.
    public let wear: SSDWear?

    public init(smart: SMARTStatus, isSolidState: Bool?, mediaName: String?, wear: SSDWear? = nil) {
        self.smart = smart
        self.isSolidState = isSolidState
        self.mediaName = mediaName
        self.wear = wear
    }

    public static let unknown = DiskHealth(smart: .unknown, isSolidState: nil, mediaName: nil)
}

/// Battery condition from `AppleSmartBattery`.
public struct BatteryHealth: Equatable {

    public let cycleCount: Int
    /// Current full-charge capacity, mAh.
    public let maximumCapacity: Int
    /// Capacity of the new battery, mAh.
    public let designCapacity: Int
    /// Present charge, mAh.
    public let currentCapacity: Int
    public let temperatureCelsius: Double?
    public let isCharging: Bool
    public let isPluggedIn: Bool

    public init(cycleCount: Int, maximumCapacity: Int, designCapacity: Int, currentCapacity: Int,
                temperatureCelsius: Double?, isCharging: Bool, isPluggedIn: Bool) {
        self.cycleCount = cycleCount
        self.maximumCapacity = maximumCapacity
        self.designCapacity = designCapacity
        self.currentCapacity = currentCapacity
        self.temperatureCelsius = temperatureCelsius
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }

    /// Remaining capacity relative to design, `0...1`.
    public var healthFraction: Double {
        designCapacity > 0 ? min(1, Double(maximumCapacity) / Double(designCapacity)) : 1
    }

    /// Loss of capacity relative to design, `0...1`.
    public var wearFraction: Double { 1 - healthFraction }

    /// Charge level, `0...1`.
    public var chargeFraction: Double {
        maximumCapacity > 0 ? min(1, Double(currentCapacity) / Double(maximumCapacity)) : 0
    }
}

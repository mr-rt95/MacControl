//
//  BatteryMonitor.swift
//  MacControlCore
//

import Foundation
import IOKit

/// Reads battery condition from the `AppleSmartBattery` IORegistry entry.
public final class BatteryMonitor {

    public init() {}

    /// Returns `nil` on Macs without a battery.
    public func read() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return Self.parse(properties)
    }

    // MARK: - Parsing (pure, unit-tested)

    static func parse(_ properties: [String: Any]) -> BatteryHealth? {
        func int(_ key: String) -> Int? { (properties[key] as? NSNumber)?.intValue }
        func bool(_ key: String) -> Bool { (properties[key] as? NSNumber)?.boolValue ?? false }

        guard bool("BatteryInstalled") || properties["CycleCount"] != nil,
              let design = int("DesignCapacity"), design > 0 else { return nil }

        // `AppleRawMaxCapacity` is the real mAh figure; `MaxCapacity` may be a percentage on newer systems.
        let maximum = int("AppleRawMaxCapacity") ?? int("MaxCapacity") ?? 0
        let current = int("AppleRawCurrentCapacity") ?? int("CurrentCapacity") ?? 0
        let temperature = int("Temperature").map { Double($0) / 100 }   // centi-degrees Celsius

        return BatteryHealth(
            cycleCount: int("CycleCount") ?? 0,
            maximumCapacity: maximum,
            designCapacity: design,
            currentCapacity: current,
            temperatureCelsius: temperature,
            isCharging: bool("IsCharging"),
            isPluggedIn: bool("ExternalConnected")
        )
    }
}

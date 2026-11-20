//
//  NVMeMonitor.swift
//  MacControlCore
//

import Foundation
import CNVMe

/// Reads SSD wear from the drive's NVMe SMART log. Returns `nil` for SATA drives, external drives and
/// any NVMe drive that does not expose the SMART interface.
public final class NVMeMonitor {

    public init() {}

    public func read() -> SSDWear? {
        var raw = MCNVMeSMART()
        guard MCReadNVMeSMART(&raw) == 1 else { return nil }
        return Self.wear(from: raw)
    }

    /// Converts the raw log page (pure, unit-tested).
    static func wear(from raw: MCNVMeSMART) -> SSDWear {
        // One data unit is 1000 blocks of 512 bytes.
        let unit: UInt64 = 512_000
        let kelvin = Double(raw.temperatureKelvin)
        return SSDWear(
            percentageUsed: Int(raw.percentageUsed),
            availableSpare: Int(raw.availableSpare),
            spareThreshold: Int(raw.availableSpareThreshold),
            criticalWarning: Int(raw.criticalWarning),
            bytesWritten: raw.dataUnitsWritten &* unit,
            bytesRead: raw.dataUnitsRead &* unit,
            powerOnHours: raw.powerOnHours,
            powerCycles: raw.powerCycles,
            unsafeShutdowns: raw.unsafeShutdowns,
            mediaErrors: raw.mediaErrors,
            temperatureCelsius: kelvin > 200 ? kelvin - 273.15 : nil   // 0 means "not reported"
        )
    }
}

//
//  MachTime.swift
//  MacControlCore
//

import Foundation

/// Conversion between Mach absolute time units and nanoseconds.
///
/// On Intel the ratio is 1:1, on Apple Silicon it is not, so the conversion
/// is always applied to keep the code architecture-independent.
enum MachTime {

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }()

    /// Converts Mach absolute time ticks to nanoseconds.
    static func nanoseconds(fromTicks ticks: UInt64) -> UInt64 {
        // Divide first when possible to avoid overflow on very large tick counts.
        let numer = UInt64(timebase.numer)
        let denom = UInt64(timebase.denom)
        if numer == denom { return ticks }
        return ticks / denom * numer + (ticks % denom) * numer / denom
    }

    /// Current monotonic time in nanoseconds.
    static var nowNanoseconds: UInt64 {
        nanoseconds(fromTicks: mach_absolute_time())
    }
}

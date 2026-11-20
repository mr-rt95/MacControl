//
//  Sysctl.swift
//  MacControlCore
//
//  Thin, type-safe wrappers around sysctlbyname(3).
//

import Foundation

/// Namespace for reading kernel state through `sysctlbyname`.
enum Sysctl {

    /// Reads a fixed-width integer value (e.g. `hw.memsize`, `kern.memorystatus_vm_pressure_level`).
    static func integer<T: FixedWidthInteger>(_ name: String, as type: T.Type = T.self) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// Reads a null-terminated string value (e.g. `hw.model`).
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Reads a plain C structure (e.g. `vm.swapusage` → `xsw_usage`).
    static func structure<T>(_ name: String, defaultValue: T) -> T? {
        var value = defaultValue
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

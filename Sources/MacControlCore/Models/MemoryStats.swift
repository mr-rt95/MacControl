//
//  MemoryStats.swift
//  MacControlCore
//

import Foundation

/// Kernel memory pressure level (`kern.memorystatus_vm_pressure_level`).
public enum MemoryPressure: Int, Equatable, Comparable {
    case normal = 1
    case warning = 2
    case critical = 4

    public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Maps a raw kernel value to a level; unknown values are treated as `.normal`.
    public init(kernelValue: Int32?) {
        switch kernelValue {
        case 2?: self = .warning
        case 4?: self = .critical
        default: self = .normal
        }
    }
}

/// Physical memory breakdown, in bytes. Mirrors the categories shown by Activity Monitor.
public struct MemoryStats: Equatable {

    public let total: UInt64
    /// Memory used by apps (anonymous pages minus purgeable).
    public let app: UInt64
    /// Memory that cannot be paged out.
    public let wired: UInt64
    /// Memory compressed by the kernel.
    public let compressed: UInt64
    /// File-backed pages that can be reclaimed (cached files).
    public let cached: UInt64
    /// Pages that are currently active.
    public let active: UInt64
    /// Pages that are currently inactive.
    public let inactive: UInt64
    /// Completely unused memory.
    public let free: UInt64
    public let swapUsed: UInt64
    public let swapTotal: UInt64
    public let pressure: MemoryPressure

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64,
                active: UInt64, inactive: UInt64, free: UInt64,
                swapUsed: UInt64, swapTotal: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.active = active
        self.inactive = inactive
        self.free = free
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressure = pressure
    }

    /// Memory in use: apps + wired + compressed (the "Memory Used" figure of Activity Monitor).
    public var used: UInt64 { app + wired + compressed }

    /// Fraction of physical memory in use, `0...1`.
    public var usedFraction: Double {
        total == 0 ? 0 : min(1, Double(used) / Double(total))
    }

    public static let empty = MemoryStats(
        total: 0, app: 0, wired: 0, compressed: 0, cached: 0,
        active: 0, inactive: 0, free: 0, swapUsed: 0, swapTotal: 0, pressure: .normal
    )
}

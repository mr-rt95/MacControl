//
//  CPUUsage.swift
//  MacControlCore
//

import Foundation

/// CPU load at a single point in time. All fractions are in `0...1`.
public struct CPUUsage: Equatable {

    /// Combined load over all logical cores.
    public let total: Double
    /// Time spent in user mode (including nice).
    public let user: Double
    /// Time spent in the kernel.
    public let system: Double
    /// Load of every logical core, in the order reported by the kernel.
    public let perCore: [Double]

    public init(total: Double, user: Double, system: Double, perCore: [Double]) {
        self.total = total
        self.user = user
        self.system = system
        self.perCore = perCore
    }

    public static let zero = CPUUsage(total: 0, user: 0, system: 0, perCore: [])
}

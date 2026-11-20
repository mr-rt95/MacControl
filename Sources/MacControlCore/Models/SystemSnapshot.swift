//
//  SystemSnapshot.swift
//  MacControlCore
//

import Foundation

/// Everything the monitors measured during one sampling pass.
public struct SystemSnapshot: Equatable {

    public let timestamp: Date
    public let cpu: CPUUsage
    public let memory: MemoryStats
    public let disk: DiskStats
    public let network: NetworkStats
    public let temperatures: [TemperatureReading]
    public let fans: [FanReading]
    public let thermalState: SystemThermalState
    /// Per-application process groups. Empty when the pass skipped process sampling.
    public let processGroups: [ProcessGroup]

    public init(timestamp: Date, cpu: CPUUsage, memory: MemoryStats, disk: DiskStats,
                network: NetworkStats, temperatures: [TemperatureReading], fans: [FanReading],
                thermalState: SystemThermalState, processGroups: [ProcessGroup]) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.temperatures = temperatures
        self.fans = fans
        self.thermalState = thermalState
        self.processGroups = processGroups
    }

    /// Highest valid temperature in a category, if any sensor of it reports data.
    public func hottest(in category: SensorCategory) -> Double? {
        temperatures
            .filter { $0.sensor.category == category }
            .compactMap(\.celsius)
            .max()
    }

    /// Headline CPU temperature: the hottest CPU sensor (cores and die), the same figure diagnostics judge by.
    /// A proximity sensor reads far cooler than the cores and would hide overheating.
    public var cpuTemperature: Double? {
        hottest(in: .cpu)
    }

    /// Worst thermal level across all sensors with data.
    public var worstThermalLevel: ThermalLevel {
        temperatures
            .compactMap { reading -> ThermalLevel? in
                guard let value = reading.celsius else { return nil }
                return ThermalLevel.classify(celsius: value, category: reading.sensor.category)
            }
            .max() ?? .normal
    }
}

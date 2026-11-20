//
//  SystemSampler.swift
//  MacControlCore
//

import Foundation

/// Runs every monitor once and assembles a `SystemSnapshot`.
///
/// Not thread-safe: monitors keep state between calls, so use one instance from a single
/// serial queue (`MonitoringService` does this).
public final class SystemSampler {

    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let diskMonitor = DiskMonitor()
    private let networkMonitor = NetworkMonitor()
    private let processMonitor = ProcessMonitor()
    private let sensorReader: SensorReader

    /// Extra processes the unprivileged scan cannot see (root's, from the helper). Called on the sampling queue.
    public var supplementalProcesses: (() -> [ProcessSample])?

    private var lastCPU = CPUUsage.zero
    private var lastMemory = MemoryStats.empty

    public init(sensorReader: SensorReader = SensorReader()) {
        self.sensorReader = sensorReader
    }

    /// Hardware model identifier of this Mac (e.g. `MacBookPro14,1`).
    public var modelIdentifier: String { sensorReader.modelIdentifier }

    /// `true` when temperatures and fans can be read on this Mac.
    public var sensorsAvailable: Bool { sensorReader.isAvailable }

    private func allProcesses() -> [ProcessSample] {
        var samples = processMonitor.sample()
        if let extra = supplementalProcesses?() {
            let known = Set(samples.map(\.pid))
            samples += extra.filter { !known.contains($0.pid) }
        }
        return samples
    }

    /// Takes a measurement. Rates (CPU, disk, network, per-process) refer to the time since the previous call.
    /// - Parameter includeProcesses: set to `false` to skip the comparatively expensive process scan.
    public func sample(includeProcesses: Bool = true) -> SystemSnapshot {
        if let cpu = cpuMonitor.sample() { lastCPU = cpu }
        if let memory = memoryMonitor.sample() { lastMemory = memory }

        return SystemSnapshot(
            timestamp: Date(),
            cpu: lastCPU,
            memory: lastMemory,
            disk: diskMonitor.sample(),
            network: networkMonitor.sample(),
            temperatures: sensorReader.readTemperatures(),
            fans: sensorReader.readFans(),
            thermalState: SystemThermalState(ProcessInfo.processInfo.thermalState),
            processGroups: includeProcesses ? ProcessGroup.group(allProcesses()) : []
        )
    }
}

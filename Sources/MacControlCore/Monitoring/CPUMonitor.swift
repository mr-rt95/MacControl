//
//  CPUMonitor.swift
//  MacControlCore
//

import Foundation

/// Measures per-core and total CPU load using `host_processor_info`.
///
/// Load is computed from the difference between two consecutive tick counters,
/// so the first call to `sample()` returns `nil`.
public final class CPUMonitor {

    private typealias CoreTicks = (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)

    private let host = mach_host_self()
    private var previous: [CoreTicks]?

    public init() {}

    /// Returns the load since the previous call, or `nil` on the first call or on failure.
    public func sample() -> CPUUsage? {
        guard let current = readTicks() else { return nil }
        defer { previous = current }
        guard let previous = previous, previous.count == current.count else { return nil }
        return Self.usage(previous: previous, current: current)
    }

    // MARK: - Private

    private static func usage(previous: [CoreTicks], current: [CoreTicks]) -> CPUUsage {
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        var totalUser: UInt64 = 0, totalSystem: UInt64 = 0, totalAll: UInt64 = 0

        for (old, new) in zip(previous, current) {
            // Counters are 32-bit and wrap; wrapping subtraction handles that.
            let user = UInt64(new.user &- old.user) + UInt64(new.nice &- old.nice)
            let system = UInt64(new.system &- old.system)
            let idle = UInt64(new.idle &- old.idle)
            let all = user + system + idle
            perCore.append(all == 0 ? 0 : Double(user + system) / Double(all))
            totalUser += user
            totalSystem += system
            totalAll += all
        }

        guard totalAll > 0 else { return CPUUsage(total: 0, user: 0, system: 0, perCore: perCore) }
        let all = Double(totalAll)
        return CPUUsage(
            total: Double(totalUser + totalSystem) / all,
            user: Double(totalUser) / all,
            system: Double(totalSystem) / all,
            perCore: perCore
        )
    }

    private func readTicks() -> [CoreTicks]? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let status = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
        guard status == KERN_SUCCESS, let info = info else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(coreCount)).map { core in
            let base = core * stride
            return (
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }
}

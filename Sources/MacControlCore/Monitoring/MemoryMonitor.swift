//
//  MemoryMonitor.swift
//  MacControlCore
//

import Foundation

/// Reads physical memory usage, swap and memory pressure.
public final class MemoryMonitor {

    private let host = mach_host_self()
    private let pageSize: UInt64
    private let totalMemory: UInt64

    public init() {
        pageSize = UInt64(Sysctl.integer("hw.pagesize", as: Int.self) ?? 4096)
        totalMemory = Sysctl.integer("hw.memsize", as: UInt64.self) ?? ProcessInfo.processInfo.physicalMemory
    }

    /// Returns the current memory breakdown, or `nil` if the kernel query fails.
    public func sample() -> MemoryStats? {
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let status = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }

        func bytes(_ pages: UInt32) -> UInt64 { UInt64(pages) * pageSize }

        // Same accounting as Activity Monitor.
        let purgeable = UInt64(vm.purgeable_count)
        let internalPages = UInt64(vm.internal_page_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0

        let swap = Sysctl.structure("vm.swapusage", defaultValue: xsw_usage())
        let pressure = MemoryPressure(kernelValue: Sysctl.integer("kern.memorystatus_vm_pressure_level", as: Int32.self))

        return MemoryStats(
            total: totalMemory,
            app: appPages * pageSize,
            wired: bytes(vm.wire_count),
            compressed: bytes(vm.compressor_page_count),
            cached: (UInt64(vm.external_page_count) + purgeable) * pageSize,
            active: bytes(vm.active_count),
            inactive: bytes(vm.inactive_count),
            free: bytes(vm.free_count &- vm.speculative_count),
            swapUsed: swap?.xsu_used ?? 0,
            swapTotal: swap?.xsu_total ?? 0,
            pressure: pressure
        )
    }
}

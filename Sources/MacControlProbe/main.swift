//
//  main.swift
//  MacControlProbe
//
//  Diagnostic CLI: prints what MacControl can read on this Mac.
//  Ask testers to run `swift run MacControlProbe` and send the output,
//  which makes it possible to extend the sensor tables for other models.
//

import Foundation
import MacControlCore

let reader = SensorReader()
print("Model:        \(reader.modelIdentifier)")
print("SMC available: \(reader.isAvailable)")

print("\nTemperatures:")
for reading in reader.readTemperatures() {
    let value = reading.celsius.map { String(format: "%.1f °C", $0) } ?? "no data"
    print("  \(reading.sensor.key)  \(reading.sensor.title.padding(toLength: 26, withPad: " ", startingAt: 0)) \(value)")
}

print("\nFans:")
for fan in reader.readFans() {
    func rpm(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "-" }
    print("  Fan \(fan.index): current \(rpm(fan.currentRPM)) rpm, min \(rpm(fan.minimumRPM)), max \(rpm(fan.maximumRPM))")
}

if CommandLine.arguments.contains("--all-keys"), let smc = SMCConnection() {
    print("\nAll SMC keys:")
    for key in smc.allKeys() {
        let value = smc.read(key: key)
        let number = value?.numeric.map { String(format: "%.2f", $0) } ?? "?"
        print("  \(key)  \(value?.type ?? "????")  \(number)")
    }
}

if CommandLine.arguments.contains("--stats") {
    let sampler = SystemSampler(sensorReader: reader)
    _ = sampler.sample()                 // first pass primes the rate counters
    Thread.sleep(forTimeInterval: 1.5)
    let s = sampler.sample()

    func mb(_ bytes: Double) -> String { String(format: "%.2f MB/s", bytes / 1_048_576) }
    func gb(_ bytes: UInt64) -> String { String(format: "%.2f GB", Double(bytes) / 1_073_741_824) }

    print("\nCPU: total \(Int(s.cpu.total * 100))%  user \(Int(s.cpu.user * 100))%  system \(Int(s.cpu.system * 100))%")
    print("  per core: \(s.cpu.perCore.map { "\(Int($0 * 100))%" }.joined(separator: " "))")
    let m = s.memory
    print("Memory: total \(gb(m.total)) used \(gb(m.used)) (app \(gb(m.app)), wired \(gb(m.wired)), compressed \(gb(m.compressed))), cached \(gb(m.cached)), free \(gb(m.free)), swap \(gb(m.swapUsed))/\(gb(m.swapTotal)), pressure \(m.pressure)")
    print("Disk: \(gb(s.disk.usedBytes)) used of \(gb(s.disk.totalBytes)), free \(gb(s.disk.availableBytes)); read \(mb(s.disk.readBytesPerSecond)) write \(mb(s.disk.writeBytesPerSecond))")
    print("Network: down \(mb(s.network.downloadBytesPerSecond)) up \(mb(s.network.uploadBytesPerSecond))")
    print("Thermal state: \(s.thermalState)")
    print("Top processes by CPU (\(s.processGroups.count) groups):")
    for g in s.processGroups.sorted(by: { $0.cpuPercent > $1.cpuPercent }).prefix(8) {
        print(String(format: "  %-28@ %6.1f%%  %8@  procs %d", g.name as NSString, g.cpuPercent, gb(g.memoryBytes) as NSString, g.processCount))
    }
    print("Per-process network (nettop, 2s):")
    for u in NetworkProcessMonitor().measure(seconds: 1).prefix(5) {
        print("  \(u.name) [\(u.pid)] in \(u.bytesIn) out \(u.bytesOut)")
    }
}

if CommandLine.arguments.contains("--diagnose") {
    let sampler = SystemSampler(sensorReader: reader)
    let service = DiagnosticsService()
    let history = HistoryStore(fileURL: nil)
    let throttleMonitor = ThrottleMonitor()
    let battery = BatteryMonitor().read()
    let disk = DiskHealthMonitor().read()

    print("\nBattery: \(battery.map { "\($0.cycleCount) cycles, \($0.maximumCapacity)/\($0.designCapacity) mAh, wear \(Int($0.wearFraction * 100))%" } ?? "none")")
    print("SSD: \(disk.smart) \(disk.mediaName ?? "")")
    print("Throttle: \(throttleMonitor.current())")

    _ = sampler.sample()
    for _ in 0..<3 {
        Thread.sleep(forTimeInterval: 1)
        let snapshot = sampler.sample()
        history.record(snapshot)
        let findings = service.evaluate(snapshot: snapshot, throttle: throttleMonitor.current(), diskHealth: disk,
                                        battery: battery, modelIdentifier: reader.modelIdentifier, history: history)
        if findings.isEmpty { print("Findings: none") }
        for finding in findings {
            print("Finding \(finding.kind) [\(finding.severity)] culprit=\(finding.culprit?.name ?? "-") action=\(finding.action)")
            finding.evidence.forEach { print("    \($0.label): \($0.value)") }
        }
    }
}

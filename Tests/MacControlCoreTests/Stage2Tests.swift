//
//  Stage2Tests.swift
//  MacControlCoreTests
//
//  Diagnostics rules, culprit tracking, history tiers and the event journal.
//

import XCTest
@testable import MacControlCore

/// Builds synthetic snapshots so the rules can be tested without touching the system.
private enum Fixture {

    static let cpuSensor = SensorDescriptor(key: "TC0E", title: "CPU Die (E)", category: .cpu)

    static let chrome = ProcessGroup(id: "/Chrome.app", name: "Chrome", pids: [1], cpuPercent: 80,
                                     memoryBytes: 1_000_000_000,
                                     diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0)

    static func snapshot(_ time: TimeInterval, cpu: Double = 0.1, temperature: Double = 50,
                         swap: UInt64 = 0, pressure: MemoryPressure = .normal, freeFraction: Double = 0.5,
                         fan: Double = 2000, groups: [ProcessGroup] = []) -> SystemSnapshot {
        let total: UInt64 = 100_000_000_000
        return SystemSnapshot(
            timestamp: Date(timeIntervalSince1970: time),
            cpu: CPUUsage(total: cpu, user: cpu, system: 0, perCore: [cpu]),
            memory: MemoryStats(total: 8_000_000_000, app: 3_000_000_000, wired: 1_000_000_000, compressed: 0,
                                cached: 0, active: 0, inactive: 0, free: 0,
                                swapUsed: swap, swapTotal: 4_000_000_000, pressure: pressure),
            disk: DiskStats(totalBytes: total, availableBytes: UInt64(Double(total) * freeFraction),
                            readBytesPerSecond: 0, writeBytesPerSecond: 0),
            network: .zero,
            temperatures: [TemperatureReading(sensor: cpuSensor, celsius: temperature)],
            fans: [FanReading(index: 0, currentRPM: fan, minimumRPM: 1200, maximumRPM: 7200)],
            thermalState: .nominal,
            processGroups: groups
        )
    }
}

final class DiagnosticsEngineTests: XCTestCase {

    func testHealthySystemHasNoFindings() {
        XCTAssertTrue(DiagnosticsEngine.evaluate(DiagnosticsInput(snapshot: Fixture.snapshot(0))).isEmpty)
    }

    func testOverheatingWithThrottlingIsCriticalAndNamesCulprit() {
        let culprit = Culprit(name: "Chrome", cpuPercent: 80, memoryBytes: 1, activeSeconds: 100)
        let input = DiagnosticsInput(snapshot: Fixture.snapshot(0, temperature: 95),
                                     throttle: ThrottleInfo(speedLimitPercent: 60, thermalState: .serious),
                                     cpuCulprit: culprit)
        let finding = DiagnosticsEngine.evaluate(input).first
        XCTAssertEqual(finding?.kind, .overheating)
        XCTAssertEqual(finding?.severity, .critical)
        XCTAssertEqual(finding?.culprit?.name, "Chrome")
        XCTAssertEqual(finding?.metrics["speedLimit"], 60)
    }

    func testDiskThresholds() {
        let warning = DiagnosticsEngine.evaluate(DiagnosticsInput(snapshot: Fixture.snapshot(0, freeFraction: 0.12)))
        XCTAssertEqual(warning.first?.severity, .warning)
        // 5 GB left on a 100 GB disk is below the 10 GB critical limit.
        let critical = DiagnosticsEngine.evaluate(DiagnosticsInput(snapshot: Fixture.snapshot(0, freeFraction: 0.05)))
        XCTAssertEqual(critical.first?.severity, .critical)
    }

    func testMemoryPressureNeedsToLastUnlessCritical() {
        let brief = DiagnosticsInput(snapshot: Fixture.snapshot(0, pressure: .warning),
                                     modelIdentifier: "MacBookPro14,1", memoryPressureSeconds: 30)
        XCTAssertTrue(DiagnosticsEngine.evaluate(brief).isEmpty)

        let sustained = DiagnosticsInput(snapshot: Fixture.snapshot(0, pressure: .warning),
                                         modelIdentifier: "MacBookPro14,1", memoryPressureSeconds: 400)
        let finding = DiagnosticsEngine.evaluate(sustained).first
        XCTAssertEqual(finding?.kind, .memoryPressure)
        XCTAssertEqual(finding?.metrics["upgradable"], 0, "MacBookPro14,1 has soldered memory")
    }

    func testMemoryUpgradability() {
        XCTAssertEqual(DiagnosticsEngine.isMemoryUpgradable(model: "MacBookPro9,2"), true)
        XCTAssertEqual(DiagnosticsEngine.isMemoryUpgradable(model: "Macmini7,1"), false)
        XCTAssertNil(DiagnosticsEngine.isMemoryUpgradable(model: "iMac18,3"))
    }

    func testCoolingSuspicion() {
        let hotIdle = Fixture.snapshot(0, cpu: 0.2, temperature: 82, fan: 6500)
        XCTAssertTrue(DiagnosticsEngine.coolingSuspected(snapshot: hotIdle, baseline: nil))
        let busy = Fixture.snapshot(0, cpu: 0.9, temperature: 85, fan: 6500)
        XCTAssertFalse(DiagnosticsEngine.coolingSuspected(snapshot: busy, baseline: nil))
        let finding = DiagnosticsEngine.evaluate(DiagnosticsInput(snapshot: hotIdle, coolingSuspicionSeconds: 130))
        XCTAssertTrue(finding.contains { $0.kind == .cooling })
    }

    func testCulpritTrackerNamesBusyApp() {
        let tracker = CulpritTracker()
        for _ in 0..<30 { tracker.update(groups: [Fixture.chrome], elapsed: 5) }
        XCTAssertEqual(tracker.cpuCulprit?.name, "Chrome")
        XCTAssertGreaterThanOrEqual(tracker.cpuCulprit?.activeSeconds ?? 0, 140)
    }
}

final class HistoryStoreTests: XCTestCase {

    func testTiersAggregateIntoBuckets() {
        let store = HistoryStore(fileURL: nil, now: Date(timeIntervalSince1970: 0))
        for i in 0..<130 { store.record(Fixture.snapshot(Double(1_000_000 + i), groups: [Fixture.chrome])) }
        let now = Date(timeIntervalSince1970: 1_000_130)
        XCTAssertEqual(store.points(for: .hour, now: now).count, 26, accuracy: 1)
        XCTAssertEqual(store.points(for: .day, now: now).count, 3, accuracy: 1)
        XCTAssertEqual(store.points(for: .hour, now: now).last?.topProcesses, ["Chrome"])
    }

    func testPersistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(timeIntervalSince1970: 1_000_130)

        let store = HistoryStore(fileURL: url, now: now)
        for i in 0..<130 { store.record(Fixture.snapshot(Double(1_000_000 + i))) }
        store.save()

        let reloaded = HistoryStore(fileURL: url, now: now)
        XCTAssertGreaterThanOrEqual(reloaded.points(for: .hour, now: now).count, 20)
    }
}

final class EventLogTests: XCTestCase {

    private let thresholds = DiagnosticsThresholds()

    func testCPUEventOpensAfterMinimumDurationAndClosesAfterGrace() {
        let log = EventLog(fileURL: nil, now: Date(timeIntervalSince1970: 0))
        for i in 0..<100 {
            log.update(snapshot: Fixture.snapshot(Double(i), cpu: 0.95, groups: [Fixture.chrome]),
                       throttle: .none, thresholds: thresholds)
        }
        XCTAssertEqual(log.events.count, 1)
        XCTAssertTrue(log.events[0].isOngoing)
        XCTAssertEqual(log.events[0].start, Date(timeIntervalSince1970: 0), "dated from when the condition began")

        for i in 100..<130 {
            log.update(snapshot: Fixture.snapshot(Double(i), cpu: 0.1), throttle: .none, thresholds: thresholds)
        }
        XCTAssertFalse(log.events[0].isOngoing)
        XCTAssertEqual(log.events[0].topProcesses, ["Chrome"])
    }

    func testShortSpikeIsNotLogged() {
        let log = EventLog(fileURL: nil, now: Date(timeIntervalSince1970: 0))
        for i in 0..<30 {
            log.update(snapshot: Fixture.snapshot(Double(i), cpu: 0.95), throttle: .none, thresholds: thresholds)
        }
        XCTAssertTrue(log.events.isEmpty)
    }

    func testThrottlingEventRecordsLowestLimit() {
        let log = EventLog(fileURL: nil, now: Date(timeIntervalSince1970: 0))
        let throttle = ThrottleInfo(speedLimitPercent: 50, thermalState: .fair)
        for i in 0..<40 {
            log.update(snapshot: Fixture.snapshot(Double(i)), throttle: throttle, thresholds: thresholds)
        }
        XCTAssertEqual(log.events.first { $0.kind == .throttling }?.lowestSpeedLimit, 50)
    }
}

final class HealthParsingTests: XCTestCase {

    func testSpeedLimitParsing() {
        let output = "Note: x\n\tCPU_Scheduler_Limit \t= 100\n\tCPU_Available_CPUs \t= 4\n\tCPU_Speed_Limit \t= 75\n"
        XCTAssertEqual(ThrottleMonitor.parseSpeedLimit(output), 75)
        XCTAssertNil(ThrottleMonitor.parseSpeedLimit("Note: nothing"))
    }

    func testBatteryParsing() {
        let battery = BatteryMonitor.parse([
            "BatteryInstalled": true, "CycleCount": 993, "AppleRawMaxCapacity": 2647,
            "DesignCapacity": 4790, "CurrentCapacity": 2525, "Temperature": 3037,
            "IsCharging": false, "ExternalConnected": true
        ])
        XCTAssertEqual(battery?.cycleCount, 993)
        XCTAssertEqual(battery?.temperatureCelsius ?? 0, 30.37, accuracy: 0.01)
        XCTAssertEqual(battery?.wearFraction ?? 0, 0.447, accuracy: 0.01)
        XCTAssertNil(BatteryMonitor.parse([:]))
    }

    func testDiskHealthParsing() {
        XCTAssertEqual(DiskHealthMonitor.parse(["SMARTStatus": "Verified"]).smart, .verified)
        XCTAssertEqual(DiskHealthMonitor.parse(["SMARTStatus": "Failing"]).smart, .failing)
        XCTAssertEqual(DiskHealthMonitor.parse([:]).smart, .unknown)
        XCTAssertEqual(DiskHealthMonitor.wholeDisk(of: "disk0s2"), "disk0")
        XCTAssertEqual(DiskHealthMonitor.wholeDisk(of: "disk12s10"), "disk12")
    }
}

private func XCTAssertEqual(_ value: Int, _ expected: Int, accuracy: Int,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(value - expected), accuracy, "\(value) is not within \(accuracy) of \(expected)",
                             file: file, line: line)
}

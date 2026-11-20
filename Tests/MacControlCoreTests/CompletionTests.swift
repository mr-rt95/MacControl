//
//  CompletionTests.swift
//  MacControlCoreTests
//
//  SSD wear, folder usage and quiet-mode crash recovery.
//

import XCTest
import CNVMe
@testable import MacControlCore

final class SSDWearTests: XCTestCase {

    func testRawLogConversion() {
        var raw = MCNVMeSMART()
        raw.dataUnitsWritten = 1_000          // one unit = 1000 × 512 bytes
        raw.temperatureKelvin = 313
        raw.percentageUsed = 12
        let wear = NVMeMonitor.wear(from: raw)
        XCTAssertEqual(wear.bytesWritten, 512_000_000)
        XCTAssertEqual(wear.temperatureCelsius ?? 0, 39.85, accuracy: 0.01)
        XCTAssertEqual(wear.percentageUsed, 12)

        raw.temperatureKelvin = 0
        XCTAssertNil(NVMeMonitor.wear(from: raw).temperatureCelsius, "0 means the drive does not report a temperature")
    }

    private func finding(used: Int, spare: Int = 90, threshold: Int = 2, warning: Int = 0) -> Finding? {
        let wear = SSDWear(percentageUsed: used, availableSpare: spare, spareThreshold: threshold, criticalWarning: warning,
                           bytesWritten: 1, bytesRead: 1, powerOnHours: 1, powerCycles: 1, unsafeShutdowns: 0,
                           mediaErrors: 0, temperatureCelsius: nil)
        let snapshot = SystemSnapshot(
            timestamp: Date(), cpu: .zero, memory: .empty,
            disk: DiskStats(totalBytes: 100, availableBytes: 90, readBytesPerSecond: 0, writeBytesPerSecond: 0),
            network: .zero, temperatures: [], fans: [], thermalState: .nominal, processGroups: [])
        let health = DiskHealth(smart: .verified, isSolidState: true, mediaName: nil, wear: wear)
        return DiagnosticsEngine.evaluate(DiagnosticsInput(snapshot: snapshot, diskHealth: health)).first { $0.kind == .ssdWear }
    }

    func testWearThresholds() {
        XCTAssertNil(finding(used: 50))
        XCTAssertEqual(finding(used: 75)?.severity, .warning)
        XCTAssertEqual(finding(used: 95)?.severity, .serious)
        XCTAssertEqual(finding(used: 10, spare: 1, threshold: 5)?.severity, .critical, "spare below the drive's own threshold")
        XCTAssertEqual(finding(used: 10, warning: 4)?.severity, .critical, "critical-warning bits")
    }
}

final class FolderUsageTests: XCTestCase {

    func testChildrenAreMeasuredAndSymlinksSkipped() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mc-folders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("big/sub"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent("small"), withIntermediateDirectories: true)
        manager.createFile(atPath: root.appendingPathComponent("big/sub/a.bin").path, contents: Data(count: 3_000_000))
        manager.createFile(atPath: root.appendingPathComponent("small/b.bin").path, contents: Data(count: 100_000))
        manager.createFile(atPath: root.appendingPathComponent("file.bin").path, contents: Data(count: 500_000))
        try manager.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/System"))

        var entries: [FolderEntry] = []
        FolderUsage().measure(folder: root) { entries.append($0) }
        entries.sort { $0.bytes > $1.bytes }

        XCTAssertEqual(entries.map(\.name), ["big", "file.bin", "small"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertFalse(entries[1].isDirectory)
    }
}

final class QuietModeRecoveryTests: XCTestCase {

    private func priority(of pid: Int32) -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "pri=", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        return Int(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 99
    }

    /// A previous run that died in quiet mode must not leave processes slowed down for good.
    func testNextLaunchRestoresProcessesLeftAtLowPriority() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mc-quiet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = folder.appendingPathComponent("quiet-state.json")
        let copy = folder.appendingPathComponent("mysleep")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: copy)

        let child = Process()
        child.executableURL = copy
        child.arguments = ["120"]
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }

        let first = PriorityController(stateURL: state)
        XCTAssertEqual(first.reconcile(targets: [child.processIdentifier]), 1)
        XCTAssertLessThan(priority(of: child.processIdentifier), 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.path))

        _ = PriorityController(stateURL: state)          // "next launch" without the first having restored anything
        XCTAssertGreaterThan(priority(of: child.processIdentifier), 20)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path))
    }
}

final class ProcessListCompletenessTests: XCTestCase {

    /// Regression: `proc_listallpids` returns a *count*; treating it as bytes cut the list to a quarter,
    /// which hid most processes and underreported load.
    func testSamplesCoverMostOfTheUsersProcesses() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-u", "\(getuid())", "-o", "pid="]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        let psCount = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .split(separator: "\n").count ?? 0

        let monitor = ProcessMonitor()
        let sampled = monitor.sample().filter { $0.uid == getuid() }.count
        XCTAssertGreaterThan(psCount, 20)
        XCTAssertGreaterThan(Double(sampled), Double(psCount) * 0.8, "sampled \(sampled) of \(psCount) processes")
    }
}

final class GraphicsAndGroupTests: XCTestCase {

    private func snapshot(temperatures: [TemperatureReading] = []) -> SystemSnapshot {
        SystemSnapshot(timestamp: Date(), cpu: .zero, memory: .empty,
                       disk: DiskStats(totalBytes: 100, availableBytes: 90, readBytesPerSecond: 0, writeBytesPerSecond: 0),
                       network: .zero, temperatures: temperatures, fans: [], thermalState: .nominal, processGroups: [])
    }

    func testGraphicsFindingNeedsSustainedWindowServerLoad() {
        let brief = DiagnosticsInput(snapshot: snapshot(), graphicsCPUPercent: 40, graphicsBusySeconds: 20)
        XCTAssertNil(DiagnosticsEngine.evaluate(brief).first { $0.kind == .graphicsLoad })

        let low = DiagnosticsInput(snapshot: snapshot(), graphicsCPUPercent: 10, graphicsBusySeconds: 300)
        XCTAssertNil(DiagnosticsEngine.evaluate(low).first { $0.kind == .graphicsLoad })

        let sustained = DiagnosticsInput(snapshot: snapshot(), graphicsCPUPercent: 40, graphicsBusySeconds: 120)
        let finding = DiagnosticsEngine.evaluate(sustained).first { $0.kind == .graphicsLoad }
        XCTAssertEqual(finding?.action, .reduceVisualEffects)
    }

    func testHeadlineTemperatureIsTheHottestCPUSensor() {
        func reading(_ key: String, _ celsius: Double) -> TemperatureReading {
            TemperatureReading(sensor: SensorDescriptor(key: key, title: key, category: .cpu), celsius: celsius)
        }
        let snap = snapshot(temperatures: [reading("TC0P", 66), reading("TC1C", 93), reading("TC0E", 101)])
        XCTAssertEqual(snap.cpuTemperature, 101, "proximity (66) must not hide the hot cores")
    }

    func testGroupsCarryProtectionFacts() {
        let samples = [
            ProcessSample(pid: 152, name: "WindowServer", groupKey: "WindowServer", groupName: "WindowServer", uid: 88,
                          cpuPercent: 40, memoryBytes: 1, diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0,
                          path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"),
            ProcessSample(pid: 500, name: "Brave Browser", groupKey: "/Applications/Brave.app", groupName: "Brave Browser", uid: 501,
                          cpuPercent: 20, memoryBytes: 1, diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0,
                          path: "/Applications/Brave.app/Contents/MacOS/Brave Browser"),
            ProcessSample(pid: 501, name: "Brave Browser Helper", groupKey: "/Applications/Brave.app", groupName: "Brave Browser", uid: 501,
                          cpuPercent: 5, memoryBytes: 1, diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0)
        ]
        let groups = ProcessGroup.group(samples)
        let windowServer = try? XCTUnwrap(groups.first { $0.name == "WindowServer" })
        XCTAssertEqual(windowServer?.ownerUID, 88)
        XCTAssertEqual(windowServer?.processName, "WindowServer")
        XCTAssertEqual(ProcessSafety.verdict(name: windowServer?.processName ?? "", path: windowServer?.executablePath,
                                              ownerUID: windowServer?.ownerUID, pid: 152, currentUID: 501),
                       .protectedSystem, "protected even though its owner is another user")
        let brave = groups.first { $0.name == "Brave Browser" }
        XCTAssertEqual(brave?.processName, "Brave Browser", "the group is described by its main process")
    }
}

final class ConditionTimerAndThrottleTests: XCTestCase {

    func testShortDipDoesNotRestartTheCount() {
        var timer = ConditionTimer(grace: 20)
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(timer.update(true, now: start), 0)
        XCTAssertEqual(timer.update(true, now: start.addingTimeInterval(30)), 30)
        XCTAssertEqual(timer.update(false, now: start.addingTimeInterval(36)), 36, "a dip shorter than the grace period is ignored")
        XCTAssertEqual(timer.update(true, now: start.addingTimeInterval(40)), 40)
        XCTAssertEqual(timer.update(false, now: start.addingTimeInterval(45)), 45)
        XCTAssertEqual(timer.update(false, now: start.addingTimeInterval(70)), 0, "a long dip ends the condition")
        XCTAssertEqual(timer.update(true, now: start.addingTimeInterval(80)), 0, "and the count starts over")
    }

    func testZeroGraceBehavesLikeTheOldTimer() {
        var timer = ConditionTimer()
        let start = Date()
        _ = timer.update(true, now: start)
        XCTAssertEqual(timer.update(false, now: start.addingTimeInterval(1)), 0)
    }

    private func hotSnapshot() -> SystemSnapshot {
        let sensor = SensorDescriptor(key: "TC0E", title: "CPU Die (E)", category: .cpu)
        return SystemSnapshot(timestamp: Date(), cpu: .zero, memory: .empty,
                              disk: DiskStats(totalBytes: 100, availableBytes: 90, readBytesPerSecond: 0, writeBytesPerSecond: 0),
                              network: .zero, temperatures: [TemperatureReading(sensor: sensor, celsius: 99)],
                              fans: [], thermalState: .nominal, processGroups: [])
    }

    func testBusyKernelTaskOnAHotCPUCountsAsThrottling() {
        // pmset reports no limit, yet kernel_task burns CPU: macOS is throttling.
        let input = DiagnosticsInput(snapshot: hotSnapshot(), kernelTaskCPUPercent: 64)
        let finding = DiagnosticsEngine.evaluate(input).first { $0.kind == .overheating }
        XCTAssertEqual(finding?.metrics["kernelTask"], 64)
        XCTAssertEqual(finding?.severity, .critical)

        let calm = DiagnosticsInput(snapshot: hotSnapshot(), kernelTaskCPUPercent: 3)
        XCTAssertEqual(DiagnosticsEngine.evaluate(calm).first { $0.kind == .overheating }?.severity, .serious)
    }
}

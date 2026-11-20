//
//  Stage4Tests.swift
//  MacControlCoreTests
//
//  Notification planning, mode planning, priority control and the exported report.
//

import XCTest
@testable import MacControlCore

final class NotificationPlannerTests: XCTestCase {

    private let culprit = Culprit(name: "Chrome", cpuPercent: 98, memoryBytes: 1, activeSeconds: 400)
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let all = Set(AlertKind.allCases)

    private func finding(_ severity: Severity) -> Finding {
        Finding(kind: .overheating, severity: severity, culprit: culprit, metrics: ["temperature": 95], action: .closeHeavyApps)
    }

    func testRepeatsAreSuppressedUntilCooldownOrWorseSeverity() {
        let planner = NotificationPlanner(cooldown: 1800, quietPeriod: 600)
        XCTAssertEqual(planner.plan(findings: [finding(.serious)], enabled: all, now: start).count, 1)
        XCTAssertTrue(planner.plan(findings: [finding(.serious)], enabled: all, now: start.addingTimeInterval(60)).isEmpty)
        XCTAssertEqual(planner.plan(findings: [finding(.critical)], enabled: all, now: start.addingTimeInterval(120)).count, 1,
                       "a worse situation is announced at once")
        XCTAssertEqual(planner.plan(findings: [finding(.critical)], enabled: all, now: start.addingTimeInterval(120 + 1801)).count, 1,
                       "and again after the cooldown")
    }

    func testNewEpisodeAfterQuietPeriodIsAnnounced() {
        let planner = NotificationPlanner(cooldown: 1800, quietPeriod: 600)
        _ = planner.plan(findings: [finding(.serious)], enabled: all, now: start)
        _ = planner.plan(findings: [], enabled: all, now: start.addingTimeInterval(700))
        XCTAssertEqual(planner.plan(findings: [finding(.serious)], enabled: all, now: start.addingTimeInterval(800)).count, 1)
    }

    func testDisabledKindsAreNeverSent() {
        let planner = NotificationPlanner()
        XCTAssertTrue(planner.plan(findings: [finding(.critical)], enabled: [.lowDisk], now: start).isEmpty)
    }

    func testFrozenAppAndLongLoadMapping() {
        let overload = Finding(kind: .cpuOverload, severity: .warning, culprit: culprit,
                               metrics: ["duration": 400, "load": 0.95], action: .closeHeavyApps)
        XCTAssertEqual(Set(NotificationPlanner.candidates(from: [overload]).map(\.kind)), [.frozenApp, .longHighLoad])

        let brief = Finding(kind: .cpuOverload, severity: .warning,
                            culprit: Culprit(name: "X", cpuPercent: 98, memoryBytes: 1, activeSeconds: 60),
                            metrics: ["duration": 70], action: .closeHeavyApps)
        XCTAssertTrue(NotificationPlanner.candidates(from: [brief]).isEmpty)
        XCTAssertTrue(NotificationPlanner.candidates(from: [Finding(kind: .batteryWear, severity: .warning, action: .replaceBattery)]).isEmpty,
                      "non-urgent findings never interrupt")
    }
}

final class ModePlannerTests: XCTestCase {

    private func group(_ id: String, _ pids: [Int32], cpu: Double, memory: UInt64 = 0) -> ProcessGroup {
        ProcessGroup(id: id, name: id, pids: pids, cpuPercent: cpu, memoryBytes: memory,
                     diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0)
    }

    func testQuietModeSparesTheActiveApp() {
        let groups = [group("front", [10, 11], cpu: 50), group("bg", [20, 21], cpu: 30), group("idle", [30], cpu: 0.1)]
        XCTAssertEqual(ModePlanner.quietTargets(groups: groups, frontmostPID: 11), [20, 21])
    }

    func testPerformanceSuggestionsAreHeaviestBackgroundAppsThatMayBeQuit() {
        let groups = [group("front", [10], cpu: 50), group("bg", [20], cpu: 30), group("bigmem", [40], cpu: 0, memory: 900_000_000)]
        XCTAssertEqual(ModePlanner.closeSuggestions(groups: groups, frontmostPID: 10, isQuittable: { _ in true }).map(\.id),
                       ["bg", "bigmem"])
        XCTAssertEqual(ModePlanner.closeSuggestions(groups: groups, frontmostPID: 10, isQuittable: { $0.id != "bg" }).map(\.id),
                       ["bigmem"])
    }
}

final class PriorityControllerTests: XCTestCase {

    func testSafetyVetoAndProtectedProcessesAreNeverTouched() {
        XCTAssertEqual(PriorityController(isAllowed: { _ in false }).reconcile(targets: [getpid()]), 0)
        XCTAssertEqual(PriorityController().reconcile(targets: [1]), 0, "pid 1 is protected")
    }

    func testLowersAndRestoresAUserProcess() throws {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("mysleep-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let child = Process()
        child.executableURL = copy
        child.arguments = ["60"]
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }

        let controller = PriorityController()
        XCTAssertEqual(controller.reconcile(targets: [child.processIdentifier]), 1)
        XCTAssertEqual(controller.affectedCount, 1)
        controller.restoreAll()
        XCTAssertEqual(controller.affectedCount, 0)
    }
}

final class ReportTests: XCTestCase {

    private func sampleReport() -> SystemReport {
        var report = SystemReport()
        report.collectSystemFacts()
        report.findings = [ReportFinding(severity: .serious, title: "Your Mac is overheating",
                                         detail: "CPU temperature is 95 °C.", advice: "Close <b>Chrome</b>.",
                                         evidence: [Evidence(label: "CPU load", value: "7%")])]
        report.topProcesses = [ReportProcess(name: "Chrome & <Co>", cpuPercent: 40, memoryBytes: 1_000_000_000)]
        report.startupItems = ["com.google.keystone.agent"]
        report.recentEvents = [LoggedEvent(kind: .overheating, start: Date().addingTimeInterval(-3600),
                                           end: Date().addingTimeInterval(-1800), peakCPU: 0.9,
                                           peakTemperature: 96, topProcesses: ["Xcode"])]
        return report
    }

    func testMarkdownContainsTheKeySections() {
        let text = ReportFormatter().markdown(sampleReport())
        for expected in ["# Mac status report", "Your Mac is overheating", "Xcode", "com.google.keystone.agent"] {
            XCTAssertTrue(text.contains(expected), expected)
        }
    }

    func testHTMLEscapesNamesAndText() {
        let html = ReportFormatter().html(sampleReport())
        XCTAssertTrue(html.contains("Chrome &amp; &lt;Co&gt;"))
        XCTAssertTrue(html.contains("&lt;b&gt;Chrome&lt;/b&gt;"))
        XCTAssertFalse(html.contains("<b>Chrome</b>"))
    }

    func testReportContainsNoHomePath() {
        let formatter = ReportFormatter()
        let report = sampleReport()
        for text in [formatter.markdown(report), formatter.html(report)] {
            XCTAssertFalse(text.contains(NSHomeDirectory()))
            XCTAssertFalse(text.contains("/Users/"))
        }
    }
}

//
//  HelperTests.swift
//  MacControlCoreTests
//
//  The privileged helper's rules and operations (run without root, on a temporary "/Library"),
//  plus a real XPC round trip against an in-process listener.
//

import XCTest
@testable import MacControlCore

final class RecordingCommands: CommandExecuting {
    var calls: [[String]] = []
    func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
        calls.append([path] + arguments)
        return (0, "")
    }
}

/// A scratch "/Library" with the folders the helper may touch.
class HelperTestCase: XCTestCase {

    var root: URL!
    var library: URL!
    var quarantine: URL!
    let commands = RecordingCommands()

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mc-helper-\(UUID().uuidString)")
        library = root.appendingPathComponent("Library")
        quarantine = root.appendingPathComponent("Quarantine")
        for folder in ["Application Support", "Caches", "LaunchDaemons", "Preferences"] {
            try FileManager.default.createDirectory(at: library.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    var operations: PrivilegedOperations {
        PrivilegedOperations(commands: commands, systemLibrary: library.path, quarantine: quarantine)
    }

    @discardableResult
    func touch(_ relativePath: String, _ content: String = "x") -> String {
        let url = library.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}

final class PrivilegedPolicyTests: HelperTestCase {

    func testSnapshotNamesAreStrict() {
        XCTAssertEqual(PrivilegedPolicy.snapshotDate(from: "com.apple.TimeMachine.2026-11-20-123456.local"), "2026-11-20-123456")
        for bad in ["2026-11-20-123456", "com.apple.TimeMachine.x; reboot", "com.apple.TimeMachine.2026-11-20", "../../etc", ""] {
            XCTAssertNil(PrivilegedPolicy.snapshotDate(from: bad), bad)
        }
    }

    func testLabelRules() {
        XCTAssertTrue(PrivilegedPolicy.isValidThirdPartyLabel("com.vendor.helper"))
        for bad in ["com.apple.x", "a b", "x;y", "ab"] { XCTAssertFalse(PrivilegedPolicy.isValidThirdPartyLabel(bad), bad) }
    }

    func testLeftoverValidation() throws {
        let valid = touch("Application Support/com.vendor.app/data")
        let folder = URL(fileURLWithPath: valid).deletingLastPathComponent().path
        func check(_ path: String, _ id: String = "com.vendor.app") -> HelperFailure? {
            PrivilegedPolicy.validateLeftover(path: path, bundleIdentifier: id, systemLibrary: library.path)
        }
        XCTAssertNil(check(folder))
        XCTAssertEqual(check(folder, "com.other.app"), .notAllowed, "name must belong to the bundle id")
        XCTAssertEqual(check(valid), .notAllowed, "nested paths are refused")
        XCTAssertEqual(check(library.appendingPathComponent("Application Support").path), .notAllowed, "the root folder itself")
        XCTAssertEqual(check(folder, "com.apple.mail"), .invalidArgument, "Apple identifiers")
        XCTAssertEqual(check("/etc/hosts"), .notAllowed)
        XCTAssertEqual(check(folder + "/../../../etc/hosts"), .notAllowed, ".. escape")

        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("Caches/com.vendor.app"),
                                                   withDestinationURL: URL(fileURLWithPath: "/System"))
        XCTAssertEqual(check(library.appendingPathComponent("Caches/com.vendor.app").path), .notAllowed, "symlinks out of /Library")
    }

    func testTerminationRules() {
        XCTAssertEqual(PrivilegedPolicy.validateTermination(pid: 1, name: "launchd", path: "/sbin/launchd"), .protectedTarget)
        XCTAssertEqual(PrivilegedPolicy.validateTermination(pid: 500, name: "WindowServer", path: "/System/Library/x"), .protectedTarget)
        XCTAssertNil(PrivilegedPolicy.validateTermination(pid: 500, name: "vendord", path: "/Library/Vendor/vendord"))
        XCTAssertEqual(PrivilegedPolicy.validateTermination(pid: getpid(), name: "x", path: nil), .protectedTarget)
    }

    func testSigningTrustParsing() {
        XCTAssertEqual(SigningTrust(infoDictionary: ["MCSigningTeamID": "ABCDE12345"]), .team("ABCDE12345"))
        let hash = String(repeating: "ab", count: 20)
        XCTAssertEqual(SigningTrust(infoDictionary: ["MCSigningCertHash": hash]), .certificate(sha1: hash.uppercased()))
        XCTAssertEqual(SigningTrust(infoDictionary: ["MCSigningTeamID": "ABCDE12345", "MCSigningCertHash": hash]),
                       .team("ABCDE12345"), "a team ID wins over a hash")
        for bad: [String: Any] in [[:], ["MCSigningTeamID": ""], ["MCSigningTeamID": "short"],
                                   ["MCSigningCertHash": "zz"], ["MCSigningCertHash": "ab"]] {
            XCTAssertNil(SigningTrust(infoDictionary: bad), "\(bad)")
        }
        XCTAssertNil(SigningTrust(infoDictionary: nil))
    }

    func testCertificateRequirementPinsTheExactCertificate() {
        let trust = SigningTrust.certificate(sha1: String(repeating: "AB", count: 20))
        XCTAssertEqual(trust.clientRequirement,
                       "identifier \"com.maccontrol.app\" and certificate leaf = H\"\(String(repeating: "AB", count: 20))\"")
        XCTAssertTrue(trust.helperRequirement.contains("com.maccontrol.helper"))
        XCTAssertFalse(trust.clientRequirement.contains("anchor apple"), "self-signed trust must not claim an Apple anchor")
    }

    func testRequirementStringsPinTheTeam() {
        XCTAssertTrue(HelperListenerDelegate.clientRequirement(teamID: "ABCDE12345").contains("certificate leaf[subject.OU] = \"ABCDE12345\""))
        XCTAssertTrue(HelperListenerDelegate.helperRequirement(teamID: "T").contains(HelperConstants.machServiceName))
    }
}

final class PrivilegedOperationsTests: HelperTestCase {

    func testSnapshotDeletionPassesOnlyTheParsedDate() {
        XCTAssertNil(operations.deleteSnapshot(named: "com.apple.TimeMachine.2026-11-20-123456.local"))
        XCTAssertEqual(commands.calls.last ?? [], ["/usr/bin/tmutil", "deletelocalsnapshots", "2026-11-20-123456"])

        let count = commands.calls.count
        XCTAssertEqual(operations.deleteSnapshot(named: "com.apple.TimeMachine.x; reboot"), .invalidArgument)
        XCTAssertEqual(commands.calls.count, count, "an invalid name never reaches tmutil")
    }

    func testLeftoverGoesToQuarantineAndCanBeRestored() throws {
        touch("Application Support/com.vendor.app/data")
        let path = library.appendingPathComponent("Application Support/com.vendor.app").path

        let id = try XCTUnwrap(try? operations.moveLeftover(path: path, bundleIdentifier: "com.vendor.app").get())
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantine.appendingPathComponent(id).appendingPathComponent("com.vendor.app/data").path),
                      "moved, not deleted")

        XCTAssertNil(operations.restore(id: id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "/data"))
        XCTAssertEqual(operations.restore(id: id), .notFound)
        XCTAssertEqual(operations.restore(id: "../../etc"), .invalidArgument)
    }

    func testTamperedManifestCannotRestoreOutsideLibrary() throws {
        touch("Application Support/com.vendor.app/data")
        let path = library.appendingPathComponent("Application Support/com.vendor.app").path
        let id = try XCTUnwrap(try? operations.moveLeftover(path: path, bundleIdentifier: "com.vendor.app").get())

        let manifest = quarantine.appendingPathComponent(id).appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        json["originalPath"] = "/etc/com.vendor.app"
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)

        XCTAssertEqual(operations.restore(id: id), .notAllowed)
        XCTAssertEqual(operations.purgeQuarantine(olderThanDays: 30), 0)
        XCTAssertEqual(operations.purgeQuarantine(olderThanDays: 30, now: Date().addingTimeInterval(31 * 86_400)), 1)
    }

    func testDaemonSwitchingUsesLaunchctlAndChecksTheLabel() {
        let plist = touch("LaunchDaemons/com.vendor.daemon.plist",
                          "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Label</key><string>com.vendor.daemon</string></dict></plist>")

        XCTAssertNil(operations.setDaemon(label: "com.vendor.daemon", plistPath: plist, enabled: false))
        XCTAssertEqual(commands.calls.first ?? [], ["/bin/launchctl", "disable", "system/com.vendor.daemon"])
        XCTAssertTrue(commands.calls.contains(["/bin/launchctl", "bootout", "system/com.vendor.daemon"]))

        XCTAssertEqual(operations.setDaemon(label: "com.other.daemon", plistPath: plist, enabled: false), .invalidArgument, "label must match the plist")
        XCTAssertEqual(operations.setDaemon(label: "com.apple.x", plistPath: plist, enabled: false), .invalidArgument)
        XCTAssertEqual(operations.setDaemon(label: "com.vendor.daemon", plistPath: library.appendingPathComponent("Preferences/x.plist").path,
                                            enabled: false), .notAllowed)
    }

    func testPowerMetricsFilter() {
        let raw = """
        noise
        Intel energy model derived package power (CPUs+GT+SA): 22.88W
        System Average frequency as fraction of nominal: 156.26% (3593.95 Mhz)
        CPU 0 duty cycles/s: active/idle [< 16 us: 98.64/252.08]
        CPU Average frequency as fraction of nominal: 156.23% (3593.19 Mhz)
        CPU 1 duty cycles/s: active/idle [< 16 us: 2611.66/1487.46]
        CPU Average frequency as fraction of nominal: 100.00% (2300.00 Mhz)
        **** Thermal pressure ****
        Current pressure level: Nominal
        other
        """
        let filtered = PrivilegedOperations.filterPowerMetrics(raw)
        XCTAssertFalse(filtered.contains("noise"))
        XCTAssertFalse(filtered.contains("98.64"), "bucket detail is dropped")

        let metrics = PowerMetrics.parse(filtered)
        XCTAssertEqual(metrics.packageWatts ?? 0, 22.88, accuracy: 0.001)
        XCTAssertEqual(metrics.averageMHz ?? 0, 3593.95, accuracy: 0.01)
        XCTAssertEqual(metrics.fractionOfNominal ?? 0, 1.5626, accuracy: 0.0001)
        XCTAssertEqual(metrics.coreMHz, [3593.19, 2300.0])
        XCTAssertEqual(metrics.thermalPressure, "Nominal")
    }

    func testTerminationRefusesProtectedProcesses() {
        XCTAssertEqual(operations.terminate(pid: 1, force: true), .protectedTarget)
        XCTAssertEqual(operations.terminate(pid: getpid(), force: false), .protectedTarget)
    }
}

final class HelperXPCTests: HelperTestCase {

    /// Talks to the real service object through an anonymous in-process XPC listener.
    func testRoundTripThroughXPC() throws {
        let listener = NSXPCListener.anonymous()
        let delegate = HelperListenerDelegate(service: HelperService(operations: operations), testingWithoutVerification: true)
        listener.delegate = delegate
        listener.resume()
        let client = HelperClient(timeout: 10) { NSXPCConnection(listenerEndpoint: listener.endpoint) }

        XCTAssertTrue(client.isReachable())
        XCTAssertEqual(client.deleteSnapshot("bogus"), .invalidArgument)
        XCTAssertNil(client.deleteSnapshot("com.apple.TimeMachine.2026-11-20-123456.local"))

        touch("Application Support/com.vendor.app/data")
        let path = library.appendingPathComponent("Application Support/com.vendor.app").path
        let id = try XCTUnwrap(try? client.moveLeftover(path: path, bundleIdentifier: "com.vendor.app").get())
        XCTAssertNil(client.restoreQuarantined(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        if case .failure(let failure) = client.moveLeftover(path: "/etc/hosts", bundleIdentifier: "com.vendor.app") {
            XCTAssertEqual(failure, .notAllowed)
        } else {
            XCTFail("a path outside the whitelist must be refused")
        }
        XCTAssertEqual(client.terminate(pid: 1, force: false), .protectedTarget)
        listener.invalidate()
    }

    func testUnsignedBuildsNeverConnect() {
        XCTAssertEqual(HelperClient(teamID: nil).deleteSnapshot("x"), .helperUnavailable)
        XCTAssertFalse(HelperClient(teamID: nil).isReachable())

        let strict = HelperListenerDelegate(service: HelperService(), requirement: nil)
        let probe = NSXPCListener.anonymous()
        XCTAssertFalse(strict.listener(probe, shouldAcceptNewConnection: NSXPCConnection(listenerEndpoint: probe.endpoint)),
                       "a helper without a team requirement refuses everyone")
    }
}

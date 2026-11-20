//
//  Stage3Tests.swift
//  MacControlCoreTests
//
//  Safety rules, cleanup scanning, leftovers, process rules and startup parsing.
//  File operations happen only in a temporary folder and use a fake Trash.
//

import XCTest
@testable import MacControlCore

/// Records what would be trashed instead of touching the real Trash.
final class FakeTrasher: FileTrashing {
    var trashed: [URL] = []
    var restored: [(from: URL, to: URL)] = []

    func trash(_ url: URL) throws -> URL? {
        trashed.append(url)
        return URL(fileURLWithPath: "/fake/trash/" + url.lastPathComponent)
    }

    func restore(from trashed: URL, to original: URL) throws {
        restored.append((trashed, original))
    }
}

/// Creates a scratch folder that is removed after each test.
class TemporaryDirectoryTestCase: XCTestCase {

    var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mc-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func write(_ relativePath: String, bytes: Int = 1000, ageInDays: Double = 0) -> URL {
        let url = root.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
        if ageInDays > 0 {
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-ageInDays * 86_400)],
                                                   ofItemAtPath: url.path)
        }
        return url
    }
}

final class ProtectedPathsTests: TemporaryDirectoryTestCase {

    private let home = URL(fileURLWithPath: "/Users/someone")

    func testSystemLocationsAreProtected() {
        let paths = ProtectedPaths(home: home)
        for path in ["/System/Library", "/usr/bin/ls", "/bin/sh", "/sbin/launchd", "/private/etc/hosts", "/Library/Preferences/x.plist"] {
            XCTAssertEqual(paths.check(URL(fileURLWithPath: path)), .systemPath, path)
        }
    }

    func testTraversalAndSymlinksCannotBypassProtection() throws {
        let paths = ProtectedPaths(home: home)
        XCTAssertEqual(paths.check(URL(fileURLWithPath: "/tmp/../System/Library")), .systemPath)

        let link = root.appendingPathComponent("sneaky")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System/Library"))
        XCTAssertEqual(ProtectedPaths().check(link), .systemPath)
    }

    func testStructuralAndPersonalFolders() {
        let paths = ProtectedPaths(home: home)
        XCTAssertEqual(paths.check(home), .structuralFolder)
        XCTAssertEqual(paths.check(home.appendingPathComponent("Library")), .structuralFolder)
        XCTAssertEqual(paths.check(URL(fileURLWithPath: "/Applications")), .structuralFolder)

        let document = home.appendingPathComponent("Documents/a.txt")
        XCTAssertEqual(paths.check(document), .personalFolder, "never selected automatically")
        XCTAssertNil(paths.check(document, allowPersonal: true), "allowed when the user picks it by hand")
        XCTAssertEqual(paths.check(home.appendingPathComponent("Documents"), allowPersonal: true), .structuralFolder)
        XCTAssertNil(paths.check(home.appendingPathComponent("Library/Caches/com.foo")))
    }

    func testAppleApplicationsAreProtected() {
        let paths = ProtectedPaths(home: home)
        XCTAssertEqual(paths.protection(forApplication: URL(fileURLWithPath: "/System/Applications/Mail.app"),
                                        bundleIdentifier: "com.apple.mail"), .appleApplication)
        XCTAssertNil(paths.protection(forApplication: URL(fileURLWithPath: "/Applications/Foo.app"),
                                      bundleIdentifier: "com.foo.bar"))
    }
}

final class SafeTrasherTests: TemporaryDirectoryTestCase {

    func testOnlyAllowedItemsReachTheTrash() {
        let fake = FakeTrasher()
        let trasher = SafeTrasher(protection: ProtectedPaths(), trasher: fake, log: ActionLog(fileURL: nil))
        let allowed = write("a/one.bin")

        let report = trasher.execute([
            TrashRequest(url: allowed, bytes: 1000),
            TrashRequest(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), bytes: 1),
            TrashRequest(url: FileManager.default.homeDirectoryForCurrentUser, bytes: 1),
            TrashRequest(url: root.appendingPathComponent("missing.bin"), bytes: 1)
        ], kind: .cleanup, title: "test")

        XCTAssertEqual(fake.trashed, [allowed])
        XCTAssertEqual(report.failures.count, 3)
        XCTAssertEqual(trasher.log.records.count, 1)
        XCTAssertEqual(trasher.log.records.first?.items.count, 1)
    }

    func testUndoRestoresOnlyWhenTrashedItemStillExists() throws {
        let fake = FakeTrasher()
        let trasher = SafeTrasher(protection: ProtectedPaths(), trasher: fake, log: ActionLog(fileURL: nil))
        let report = trasher.execute([TrashRequest(url: write("a/one.bin"), bytes: 1000)], kind: .cleanup, title: "test")

        // The fake trash path does not exist on disk, so nothing can be restored.
        let result = trasher.undo(recordID: try XCTUnwrap(report.recordID))
        XCTAssertEqual(result.restored, 0)
        XCTAssertEqual(result.failed, 1)
    }
}

final class CleanupScannerTests: TemporaryDirectoryTestCase {

    func testWhitelistAgeAndAppleExclusion() {
        let home = root.appendingPathComponent("home")
        for path in ["Library/Caches/com.apple.thing/x", "Library/Caches/com.foo.app/x", "Library/Caches/Bar/y"] {
            write("home/" + path, bytes: path.contains("Bar") ? 9000 : 4000)
        }
        write("home/Downloads/old.dmg", bytes: 3000, ageInDays: 120)
        write("home/Downloads/new.dmg", bytes: 3000, ageInDays: 1)
        write("tmpdir/stale.tmp", bytes: 1500, ageInDays: 5)
        write("tmpdir/fresh.tmp", bytes: 1500)

        let scanner = CleanupScanner(home: home, temporaryDirectory: root.appendingPathComponent("tmpdir"))
        XCTAssertEqual(scanner.scan(.userCaches).items.map(\.name), ["Bar", "com.foo.app"], "Apple caches excluded, biggest first")
        XCTAssertEqual(scanner.scan(.oldDownloads).items.map(\.name), ["old.dmg"])
        XCTAssertEqual(scanner.scan(.temporaryFiles).items.map(\.name), ["stale.tmp"])
        XCTAssertTrue(scanner.scan(.userCaches).items.allSatisfy { $0.risk == .safe })
        XCTAssertEqual(scanner.scan(.oldDownloads).items.first?.risk, .personal)
    }
}

final class LeftoverFinderTests: TemporaryDirectoryTestCase {

    func testFindsRelatedItemsButNotLookAlikes() throws {
        let library = root.appendingPathComponent("lib")
        let related = ["Application Support/Slack", "Caches/com.vendor.app", "Preferences/com.vendor.app.plist",
                       "Group Containers/TEAMID.com.vendor.app", "Saved Application State/com.vendor.app.savedState"]
        let unrelated = ["Application Support/SlackLike", "Preferences/com.vendor.appX.plist", "Caches/Other.app"]
        for path in related + unrelated {
            try FileManager.default.createDirectory(at: library.appendingPathComponent(path), withIntermediateDirectories: true)
            write("lib/" + path + "/f")
        }

        let finder = LeftoverFinder(userLibrary: library, systemLibrary: root.appendingPathComponent("syslib"))
        let names = Set(finder.find(bundleIdentifier: "com.vendor.app", appName: "Slack").map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["Slack", "com.vendor.app", "com.vendor.app.plist", "TEAMID.com.vendor.app", "com.vendor.app.savedState"])
    }

    func testAppleAppsAndShortIdentifiersAreIgnored() {
        let finder = LeftoverFinder(userLibrary: root, systemLibrary: root)
        XCTAssertTrue(finder.find(bundleIdentifier: "com.apple.mail", appName: "Mail").isEmpty)
        XCTAssertNil(LeftoverFinder.usable(identifier: "x"))
    }
}

final class ProcessSafetyTests: XCTestCase {

    func testVerdicts() {
        func verdict(_ name: String, _ path: String?, owner: UInt32 = 501, pid: Int32 = 600) -> ProcessVerdict {
            ProcessSafety.verdict(name: name, path: path, ownerUID: owner, pid: pid, currentUID: 501, ownPID: 77)
        }
        XCTAssertEqual(verdict("kernel_task", nil, owner: 0, pid: 0), .protectedSystem)
        XCTAssertEqual(verdict("WindowServer", "/System/Library/PrivateFrameworks/SkyLight.framework/WindowServer"), .protectedSystem)
        XCTAssertEqual(verdict("launchd", "/sbin/launchd", owner: 0, pid: 1), .protectedSystem)
        XCTAssertEqual(verdict("ls", "/bin/ls"), .protectedSystem)
        XCTAssertEqual(verdict("Safari", "/Applications/Safari.app/Contents/MacOS/Safari"), .allowed)
        XCTAssertEqual(verdict("node", "/usr/local/bin/node"), .allowed, "user tools stay quit-able")
        XCTAssertEqual(verdict("daemon", "/x/daemon", owner: 0), .otherUser)
        XCTAssertEqual(verdict("me", "/x/me", pid: 77), .ownProcess)
    }

    func testProtectedProcessesCannotBeTerminated() {
        let terminator = ProcessTerminator()
        XCTAssertEqual(terminator.requestQuit(pids: [1])[1], .denied(.protectedSystem))
        XCTAssertEqual(terminator.forceQuit(pids: [getpid()])[getpid()], .denied(.ownProcess))
    }

    func testPoliteQuitStopsAUserProcess() throws {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("mysleep-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let child = Process()
        child.executableURL = copy
        child.arguments = ["300"]
        try child.run()

        let terminator = ProcessTerminator()
        XCTAssertEqual(terminator.requestQuit(pids: [child.processIdentifier])[child.processIdentifier], .requested)
        child.waitUntilExit()
        XCTAssertFalse(child.isRunning)
    }
}

final class StartupParsingTests: TemporaryDirectoryTestCase {

    func testLaunchctlOutput() {
        let list = "PID\tStatus\tLabel\n-\t0\tcom.foo.idle\n123\t0\tcom.foo.run\n"
        XCTAssertEqual(Launchctl.parseList(list)["com.foo.run"], .some(123))
        XCTAssertEqual(Launchctl.parseList(list)["com.foo.idle"], .some(nil))

        let disabled = "disabled services = {\n\t\"com.a.b\" => disabled\n\t\"com.c.d\" => enabled\n\t\"com.e.f\" => true\n}"
        XCTAssertEqual(Launchctl.parseDisabled(disabled), ["com.a.b", "com.e.f"])
    }

    func testLaunchPlistAndKnowledge() throws {
        let plist = root.appendingPathComponent("com.google.keystone.agent.plist")
        try """
        <?xml version="1.0"?><plist version="1.0"><dict>
        <key>Label</key><string>com.google.keystone.agent</string>
        <key>ProgramArguments</key><array><string>/Library/Google/ks</string></array>
        <key>RunAtLoad</key><true/><key>KeepAlive</key><dict/></dict></plist>
        """.write(to: plist, atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(LaunchItemsScanner.parse(plistAt: plist, scope: .userAgent))
        XCTAssertEqual(item.label, "com.google.keystone.agent")
        XCTAssertTrue(item.runsAtLoad)
        XCTAssertTrue(item.keepsAlive)
        XCTAssertEqual(item.safety, .safe)
        XCTAssertEqual(item.vendor, "google")
    }

    func testSystemAndAppleItemsCannotBeChanged() throws {
        func item(label: String, scope: LaunchScope) -> LaunchItem {
            LaunchItem(label: label, plistURL: root, scope: scope, program: nil, runsAtLoad: true, keepsAlive: false, isDisabled: false)
        }
        XCTAssertEqual(failure(LaunchItemController.setEnabled(false, item: item(label: "com.apple.x", scope: .userAgent))), .protectedSystemService)
        XCTAssertEqual(failure(LaunchItemController.setEnabled(false, item: item(label: "com.x.y", scope: .globalDaemon))), .requiresAdministrator)
    }

    func testLoginItemsAndSnapshots() {
        XCTAssertEqual(LoginItemsService.parse("Dropbox\t/Applications/Dropbox.app\nFoo\t/x/Foo.app\n").count, 2)
        XCTAssertEqual(LoginItemsService.escape("a\"b\\c"), "a\\\"b\\\\c")
        XCTAssertEqual(TimeMachineSnapshots.parse("Snapshots for disk /:\ncom.apple.TimeMachine.2026-11-20-123456.local\n").count, 1)
    }

    private func failure(_ result: Result<Void, LaunchItemController.Failure>) -> LaunchItemController.Failure? {
        if case .failure(let error) = result { return error }
        return nil
    }
}

final class FileFinderTests: TemporaryDirectoryTestCase {

    func testDuplicatesNeedIdenticalContent() {
        write("d/a.bin", bytes: 2_000_000)
        write("d/sub/b.bin", bytes: 2_000_000)
        var different = Data(repeating: 7, count: 2_000_000)
        different[1_999_999] = 9                                   // same size, different tail
        FileManager.default.createFile(atPath: root.appendingPathComponent("d/c.bin").path, contents: different)
        write("d/small1.bin", bytes: 10)
        write("d/small2.bin", bytes: 10)

        let groups = DuplicateFinder(roots: [root.appendingPathComponent("d")]).find()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.map(\.lastPathComponent).sorted(), ["a.bin", "b.bin"])
        XCTAssertEqual(groups.first?.wastedBytes, 2_000_000)
    }

    func testLargeFilesRespectThreshold() {
        write("l/big.bin", bytes: 2_000_000)
        write("l/small.bin", bytes: 100)
        let found = LargeFileFinder(roots: [root.appendingPathComponent("l")]).find(minimumBytes: 1_000_000)
        XCTAssertEqual(found.map(\.url.lastPathComponent), ["big.bin"])
    }
}

final class TuningServiceTests: TemporaryDirectoryTestCase {

    /// Uses a private defaults domain, so real system settings are never changed.
    func testApplyAndRestoreOfAKeyThatDidNotExist() {
        let service = TuningService(backupURL: root.appendingPathComponent("backup.json"))
        let rec = TuningRecommendation(id: "t", title: "t", effect: "t", risk: .low,
                                       domain: "com.maccontrol.selftest", key: "flag", kind: .bool,
                                       desiredValue: "1", restart: .none, mayNeedPermission: false)
        defer { _ = CommandRunner.execute("/usr/bin/defaults", ["delete", "com.maccontrol.selftest"]) }

        XCTAssertNil(service.currentValue(of: rec))
        XCTAssertEqual(service.apply(rec), .applied)
        XCTAssertTrue(service.isApplied(rec))
        XCTAssertTrue(service.canRestore(rec))
        XCTAssertEqual(service.apply(rec), .applied, "a second apply keeps the true original")
        XCTAssertEqual(service.restore(rec), .applied)
        XCTAssertNil(service.currentValue(of: rec), "restoring deletes a key that was not set before")
    }

    /// A failed write must not leave a backup that would show a false "Restore as it was".
    func testFailedApplyLeavesNoBackup() {
        let service = TuningService(backupURL: root.appendingPathComponent("backup.json"))
        let rec = TuningRecommendation(id: "blocked", title: "t", effect: "t", risk: .low,
                                       domain: "/System/maccontrol-write-test", key: "flag",   // the system volume is read-only
                                       kind: .bool, desiredValue: "1", restart: .none, mayNeedPermission: false)
        XCTAssertEqual(service.apply(rec), .failed)
        XCTAssertFalse(service.canRestore(rec))
    }

    func testProtectedAccessibilitySettingsAreMarkedForManualChange() {
        let manual = Set(TuningRecommendation.all.filter(\.requiresSystemSettings).map(\.id))
        XCTAssertEqual(manual, ["reduceTransparency", "reduceMotion"])
    }
}

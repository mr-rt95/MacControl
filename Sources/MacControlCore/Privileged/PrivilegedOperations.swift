//
//  PrivilegedOperations.swift
//  MacControlCore
//

import Foundation

/// Runs tools for the helper. Abstracted so the operations can be tested without root.
public protocol CommandExecuting {
    func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String)?
}

public struct SystemCommands: CommandExecuting {
    public init() {}
    public func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
        CommandRunner.execute(path, arguments, timeout: timeout).map { ($0.status, $0.output) }
    }
}

/// The actions the helper performs as root. Every method validates its input with `PrivilegedPolicy` first.
public final class PrivilegedOperations {

    private struct QuarantineManifest: Codable {
        let id: String
        let originalPath: String
        let storedName: String
        let date: Date
    }

    private let commands: CommandExecuting
    private let systemLibrary: String
    private let quarantine: URL
    private let fileManager = FileManager.default
    /// Kept between calls so CPU and disk rates can be computed.
    private let processMonitor = ProcessMonitor()
    private let processLock = NSLock()

    /// - Parameters:
    ///   - systemLibrary: the `/Library` folder (injectable for tests).
    ///   - quarantine: where moved leftovers are kept until restored or purged.
    public init(commands: CommandExecuting = SystemCommands(), systemLibrary: String = "/Library",
                quarantine: URL = URL(fileURLWithPath: "/Library/Application Support/MacControl/Quarantine")) {
        self.commands = commands
        self.systemLibrary = systemLibrary
        self.quarantine = quarantine
    }

    // MARK: - Time Machine

    public func deleteSnapshot(named name: String) -> HelperFailure? {
        guard let date = PrivilegedPolicy.snapshotDate(from: name) else { return .invalidArgument }
        guard let result = commands.run("/usr/bin/tmutil", ["deletelocalsnapshots", date], timeout: 60) else { return .operationFailed }
        return result.status == 0 ? nil : .operationFailed
    }

    // MARK: - Leftovers

    /// Moves a leftover into quarantine (never deletes it). Returns the quarantine id.
    public func moveLeftover(path: String, bundleIdentifier: String) -> Result<String, HelperFailure> {
        if let failure = PrivilegedPolicy.validateLeftover(path: path, bundleIdentifier: bundleIdentifier, systemLibrary: systemLibrary) {
            return .failure(failure)
        }
        let id = UUID().uuidString
        let folder = quarantine.appendingPathComponent(id)
        let source = URL(fileURLWithPath: path)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            try fileManager.moveItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
            let manifest = QuarantineManifest(id: id, originalPath: path, storedName: source.lastPathComponent, date: Date())
            try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
            return .success(id)
        } catch {
            try? fileManager.removeItem(at: folder)
            return .failure(.operationFailed)
        }
    }

    /// Restores a quarantined item to its original place, unless something else is there now.
    public func restore(id: String) -> HelperFailure? {
        guard UUID(uuidString: id) != nil else { return .invalidArgument }
        let folder = quarantine.appendingPathComponent(id)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(QuarantineManifest.self, from: data) else { return .notFound }

        // The original location is re-validated: a tampered manifest must not become a way to write elsewhere.
        let original = URL(fileURLWithPath: manifest.originalPath)
        let parent = original.deletingLastPathComponent().resolvingSymlinksInPath().path
        let library = URL(fileURLWithPath: systemLibrary).resolvingSymlinksInPath().path
        guard PrivilegedPolicy.leftoverRoots.contains(where: { parent == library + "/" + $0 }),
              original.lastPathComponent == manifest.storedName,
              !fileManager.fileExists(atPath: original.path) else { return .notAllowed }
        do {
            try fileManager.moveItem(at: folder.appendingPathComponent(manifest.storedName), to: original)
            try? fileManager.removeItem(at: folder)
            return nil
        } catch {
            return .operationFailed
        }
    }

    /// Permanently removes quarantined items older than `days`. Called by the helper at start-up.
    @discardableResult
    public func purgeQuarantine(olderThanDays days: Int, now: Date = Date()) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(at: quarantine, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for folder in entries {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONDecoder().decode(QuarantineManifest.self, from: data),
                  now.timeIntervalSince(manifest.date) > Double(days) * 86_400 else { continue }
            if (try? fileManager.removeItem(at: folder)) != nil { removed += 1 }
        }
        return removed
    }

    // MARK: - Launch daemons

    public func setDaemon(label: String, plistPath: String, enabled: Bool) -> HelperFailure? {
        guard PrivilegedPolicy.isValidThirdPartyLabel(label) else { return .invalidArgument }
        guard PrivilegedPolicy.isSystemDaemonPlist(path: plistPath, systemLibrary: systemLibrary) else { return .notAllowed }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return .notFound }
        guard plist["Label"] as? String == label else { return .invalidArgument }   // the label must belong to that plist

        let target = "system/\(label)"
        if enabled {
            guard commands.run("/bin/launchctl", ["enable", target], timeout: 15)?.status == 0 else { return .operationFailed }
            _ = commands.run("/bin/launchctl", ["bootstrap", "system", plistPath], timeout: 15)
        } else {
            guard commands.run("/bin/launchctl", ["disable", target], timeout: 15)?.status == 0 else { return .operationFailed }
            _ = commands.run("/bin/launchctl", ["bootout", target], timeout: 15)   // fails harmlessly if not loaded
        }
        return nil
    }

    // MARK: - Processes

    public func terminate(pid: Int32, force: Bool) -> HelperFailure? {
        if let failure = PrivilegedPolicy.validateTermination(pid: pid, name: ProcessMonitor.processName(pid: pid),
                                                              path: ProcessMonitor.executablePath(pid: pid)) {
            return failure
        }
        return kill(pid, force ? SIGKILL : SIGTERM) == 0 ? nil : .operationFailed
    }

    // MARK: - Process list

    /// Samples every process (the helper runs as root, so none are hidden).
    public func processSamples() -> Result<Data, HelperFailure> {
        processLock.lock()
        let samples = processMonitor.sample()
        processLock.unlock()
        guard let data = try? JSONEncoder().encode(samples) else { return .failure(.operationFailed) }
        return .success(data)
    }

    // MARK: - powermetrics

    /// Trimmed `powermetrics` output; see `PowerMetrics.parse`.
    public func powerMetrics() -> Result<String, HelperFailure> {
        guard let result = commands.run("/usr/bin/powermetrics", ["--samplers", "cpu_power,thermal", "-n", "1", "-i", "500"],
                                        timeout: 20) else { return .failure(.operationFailed) }
        guard result.status == 0 else { return .failure(.operationFailed) }
        return .success(Self.filterPowerMetrics(result.output))
    }

    /// Keeps only what `PowerMetrics` needs: package power, frequencies, thermal pressure. A per-core
    /// "CPU N duty cycles…" line is reduced to a "CPU N" marker so each following frequency can be attributed.
    static func filterPowerMetrics(_ output: String) -> String {
        var kept: [String] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("cpu "), lower.contains(" duty cycles"),
               let index = line.dropFirst(4).split(separator: " ").first, Int(index) != nil {
                kept.append("CPU \(index)")
            } else if lower.contains("average frequency as fraction of nominal") || lower.contains("package power")
                        || lower.contains("pressure level") || lower.contains("throttl") {
                kept.append(line)
            }
        }
        return kept.prefix(80).joined(separator: "\n")
    }
}

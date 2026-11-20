//
//  TuningService.swift
//  MacControlCore
//

import Foundation

public enum TuningResult: Equatable {
    case applied
    /// The write succeeded but macOS did not keep the value (usually a missing Accessibility permission).
    case notAccepted
    case failed
}

/// Applies and reverts tuning recommendations with `defaults`, always saving the original value first.
public final class TuningService {

    private let backupURL: URL?
    private let lock = NSLock()
    private let defaultsPath = "/usr/bin/defaults"

    public init(backupURL: URL? = AppSupport.directory?.appendingPathComponent("tuning-backup.json")) {
        self.backupURL = backupURL
    }

    /// Current value as `defaults read` prints it, or `nil` when the key is not set.
    public func currentValue(of rec: TuningRecommendation) -> String? {
        guard let result = CommandRunner.execute(defaultsPath, ["read", rec.domain, rec.key]), result.succeeded else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func isApplied(_ rec: TuningRecommendation) -> Bool {
        currentValue(of: rec) == rec.desiredValue
    }

    /// `true` if MacControl changed this setting and can restore it.
    public func canRestore(_ rec: TuningRecommendation) -> Bool {
        loadBackups()[rec.id] != nil
    }

    public func apply(_ rec: TuningRecommendation) -> TuningResult {
        let savedNow = rememberOriginal(of: rec)
        func undoBackup() {
            // Nothing changed, so there is nothing to restore: do not leave a misleading backup behind.
            guard savedNow else { return }
            var backups = loadBackups()
            backups[rec.id] = nil
            saveBackups(backups)
        }
        guard write(rec, value: rec.desiredValue) else { undoBackup(); return .failed }
        restartIfNeeded(rec)
        if isApplied(rec) { return .applied }
        undoBackup()
        return .notAccepted
    }

    /// Puts the setting back to what it was before MacControl changed it.
    public func restore(_ rec: TuningRecommendation) -> TuningResult {
        guard let original = loadBackups()[rec.id] else { return .failed }
        let ok: Bool
        if original.wasPresent, let value = original.value {
            ok = write(rec, value: value)
        } else {
            // Not set before: removing the key returns macOS to its default.
            ok = CommandRunner.execute(defaultsPath, ["delete", rec.domain, rec.key]) != nil
        }
        guard ok else { return .failed }
        restartIfNeeded(rec)
        var backups = loadBackups()
        backups[rec.id] = nil
        saveBackups(backups)
        return .applied
    }

    /// `true` when Spotlight indexing is on, `false` when off, `nil` if unknown.
    public func spotlightIndexingEnabled() -> Bool? {
        guard let result = CommandRunner.execute("/usr/bin/mdutil", ["-s", "/"]), result.succeeded else { return nil }
        let text = result.output.lowercased()
        if text.contains("indexing enabled") { return true }
        if text.contains("indexing disabled") { return false }
        return nil
    }

    // MARK: - Private

    private func write(_ rec: TuningRecommendation, value: String) -> Bool {
        let arguments: [String]
        switch rec.kind {
        case .bool:   arguments = ["write", rec.domain, rec.key, "-bool", value == "1" ? "true" : "false"]
        case .string: arguments = ["write", rec.domain, rec.key, "-string", value]
        }
        return CommandRunner.execute(defaultsPath, arguments)?.succeeded == true
    }

    private func restartIfNeeded(_ rec: TuningRecommendation) {
        if rec.restart == .dock { _ = CommandRunner.execute("/usr/bin/killall", ["Dock"]) }
    }

    /// Saves the pre-change value once; a second apply must not overwrite the true original.
    /// - Returns: `true` if a backup was created by this call.
    @discardableResult
    private func rememberOriginal(of rec: TuningRecommendation) -> Bool {
        var backups = loadBackups()
        guard backups[rec.id] == nil else { return false }
        let current = currentValue(of: rec)
        backups[rec.id] = OriginalValue(wasPresent: current != nil, value: current)
        saveBackups(backups)
        return true
    }

    private func loadBackups() -> [String: OriginalValue] {
        lock.lock()
        defer { lock.unlock() }
        guard let url = backupURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: OriginalValue].self, from: data)) ?? [:]
    }

    private func saveBackups(_ backups: [String: OriginalValue]) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = backupURL, let data = try? JSONEncoder().encode(backups) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

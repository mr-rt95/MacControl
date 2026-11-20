//
//  LaunchItemsScanner.swift
//  MacControlCore
//

import Foundation

/// Reads launchd job definitions and joins them with their state and resource use.
public final class LaunchItemsScanner {

    private let locations: [(URL, LaunchScope)]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        locations = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .globalDaemon),
            (URL(fileURLWithPath: "/System/Library/LaunchAgents"), .system),
            (URL(fileURLWithPath: "/System/Library/LaunchDaemons"), .system)
        ]
    }

    /// - Parameter groups: current process groups, used to attach CPU and memory to running jobs.
    public func scan(processGroups: [ProcessGroup] = []) -> [LaunchItem] {
        let running = Launchctl.runningJobs()
        let disabled = Launchctl.disabledLabels()
        let usage = Dictionary(uniqueKeysWithValues: processGroups.flatMap { group in
            group.pids.map { ($0, (group.cpuPercent / Double(max(group.pids.count, 1)), group.memoryBytes / UInt64(max(group.pids.count, 1)))) }
        })

        var items: [LaunchItem] = []
        for (directory, scope) in locations {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let url = directory.appendingPathComponent(file)
                guard var item = Self.parse(plistAt: url, scope: scope) else { continue }
                item.isDisabled = disabled.contains(item.label) || item.isDisabled
                if let pid = running[item.label] ?? nil {
                    item.pid = pid
                    item.cpuPercent = usage[pid]?.0 ?? 0
                    item.memoryBytes = usage[pid]?.1 ?? 0
                }
                items.append(item)
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Parses one launchd plist. Returns `nil` for files that are not valid job definitions.
    static func parse(plistAt url: URL, scope: LaunchScope) -> LaunchItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else { return nil }

        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let keepAlive: Bool
        switch plist["KeepAlive"] {
        case let flag as Bool: keepAlive = flag
        case is [String: Any]: keepAlive = true
        default: keepAlive = false
        }
        return LaunchItem(label: label, plistURL: url, scope: scope, program: program,
                          runsAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepsAlive: keepAlive,
                          isDisabled: plist["Disabled"] as? Bool ?? false)
    }
}

/// Enables and disables launchd jobs without deleting them.
public enum LaunchItemController {

    public enum Failure: Error, Equatable {
        case requiresAdministrator
        case protectedSystemService
        case commandFailed
    }

    /// Disables or re-enables a launchd job. Apple services are always refused; system daemons need the helper.
    public static func setEnabled(_ enabled: Bool, item: LaunchItem, helper: HelperClient? = nil) -> Result<Void, Failure> {
        if item.isApple || item.scope == .system { return .failure(.protectedSystemService) }

        if item.scope == .globalDaemon {
            guard let helper = helper else { return .failure(.requiresAdministrator) }
            let failure = helper.setDaemon(label: item.label, plistPath: item.plistURL.path, enabled: enabled)
            return failure == nil ? .success(()) : .failure(.commandFailed)
        }
        let ok = enabled ? Launchctl.enable(label: item.label, plist: item.plistURL)
                         : Launchctl.disable(label: item.label, plist: item.plistURL)
        return ok ? .success(()) : .failure(.commandFailed)
    }
}

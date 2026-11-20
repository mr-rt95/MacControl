//
//  ThrottleMonitor.swift
//  MacControlCore
//

import Foundation

/// Detects CPU throttling without administrator rights.
///
/// `pmset -g therm` is spawned at most every `minimumInterval` seconds and its last result is
/// reused in between, so the cost is negligible.
public final class ThrottleMonitor {

    private let minimumInterval: TimeInterval
    private var lastRun: Date = .distantPast
    private var lastLimit: Int?

    public init(minimumInterval: TimeInterval = 10) {
        self.minimumInterval = minimumInterval
    }

    public func current(now: Date = Date()) -> ThrottleInfo {
        if now.timeIntervalSince(lastRun) >= minimumInterval {
            lastRun = now
            lastLimit = Self.readSpeedLimit()
        }
        return ThrottleInfo(speedLimitPercent: lastLimit,
                            thermalState: SystemThermalState(ProcessInfo.processInfo.thermalState))
    }

    // MARK: - Parsing (pure, unit-tested)

    /// Extracts `CPU_Speed_Limit` from `pmset -g therm` output.
    static func parseSpeedLimit(_ output: String) -> Int? {
        for line in output.split(separator: "\n") where line.contains("CPU_Speed_Limit") {
            guard let equals = line.lastIndex(of: "=") else { continue }
            return Int(line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func readSpeedLimit() -> Int? {
        guard let output = CommandRunner.run("/usr/bin/pmset", ["-g", "therm"]) else { return nil }
        return parseSpeedLimit(output)
    }
}

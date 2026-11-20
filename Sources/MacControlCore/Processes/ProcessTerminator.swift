//
//  ProcessTerminator.swift
//  MacControlCore
//

import Foundation
import AppKit

/// Outcome of asking one process to quit.
public enum TerminationOutcome: Equatable {
    case requested
    case denied(ProcessVerdict)
    case failed(Int32)       // errno
}

/// Quits processes: politely first, forcefully only when the user asks again.
///
/// Every call re-checks `ProcessSafety`, so protected processes cannot be terminated even if a
/// caller passes them in.
public final class ProcessTerminator {

    public init() {}

    /// Asks the processes to quit. Applications get a normal quit request (`NSRunningApplication`),
    /// other processes receive `SIGTERM`. Unsaved documents may prompt the user.
    public func requestQuit(pids: [Int32]) -> [Int32: TerminationOutcome] {
        var outcomes: [Int32: TerminationOutcome] = [:]
        for pid in pids {
            let verdict = ProcessSafety.verdict(for: pid)
            guard verdict == .allowed else { outcomes[pid] = .denied(verdict); continue }

            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited || app.bundleIdentifier != nil {
                outcomes[pid] = app.terminate() ? .requested : sendSignal(SIGTERM, to: pid)
            } else {
                outcomes[pid] = sendSignal(SIGTERM, to: pid)
            }
        }
        return outcomes
    }

    /// Immediately kills processes that ignored the polite request (`SIGKILL`). Unsaved data is lost.
    public func forceQuit(pids: [Int32]) -> [Int32: TerminationOutcome] {
        var outcomes: [Int32: TerminationOutcome] = [:]
        for pid in pids {
            let verdict = ProcessSafety.verdict(for: pid)
            guard verdict == .allowed else { outcomes[pid] = .denied(verdict); continue }
            outcomes[pid] = sendSignal(SIGKILL, to: pid)
        }
        return outcomes
    }

    /// Waits up to `timeout` seconds and returns the pids that are still running.
    public func waitForExit(pids: [Int32], timeout: TimeInterval) -> [Int32] {
        let deadline = Date().addingTimeInterval(timeout)
        var remaining = pids.filter(Self.isRunning)
        while !remaining.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            remaining = remaining.filter(Self.isRunning)
        }
        return remaining
    }

    /// `kill(pid, 0)` probes existence without sending a signal.
    public static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func sendSignal(_ signal: Int32, to pid: Int32) -> TerminationOutcome {
        kill(pid, signal) == 0 ? .requested : .failed(errno)
    }
}

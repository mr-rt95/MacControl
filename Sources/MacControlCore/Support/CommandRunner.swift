//
//  CommandRunner.swift
//  MacControlCore
//

import Foundation

/// Runs a system tool and captures its standard output. Only for rarely-needed data
/// that has no API (`pmset`, `diskutil`); hot paths use system calls instead.
enum CommandRunner {

    /// Returns standard output, or `nil` if the tool is missing, fails to start or exits non-zero.
    static func run(_ path: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Result of a tool run with a time limit.
struct CommandResult {
    let status: Int32
    let output: String
    let error: String
    var succeeded: Bool { status == 0 }
}

extension CommandRunner {

    /// Runs a tool, capturing stdout and stderr, and terminates it after `timeout` seconds.
    /// Returns `nil` only when the tool cannot be started.
    static func execute(_ path: String, _ arguments: [String], timeout: TimeInterval = 15) -> CommandResult? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        var errorData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errorData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outputData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()

        return CommandResult(status: process.terminationStatus,
                             output: String(data: outputData, encoding: .utf8) ?? "",
                             error: String(data: errorData, encoding: .utf8) ?? "")
    }
}

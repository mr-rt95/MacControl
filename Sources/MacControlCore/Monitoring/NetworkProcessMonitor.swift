//
//  NetworkProcessMonitor.swift
//  MacControlCore
//

import Foundation

/// Per-process network traffic, obtained from `nettop`.
///
/// libproc does not expose network counters, so `nettop` is the only unprivileged source.
/// A measurement takes about one second, therefore it runs on demand (only while the
/// Network screen is visible) and never on the main thread.
public final class NetworkProcessMonitor {

    private static let nettopPath = "/usr/bin/nettop"

    public init() {}

    /// Measures traffic of every process for `seconds` and returns the busiest first.
    /// Returns an empty array when `nettop` is unavailable or its output cannot be parsed.
    public func measure(seconds: Int = 1) -> [ProcessNetworkUsage] {
        guard FileManager.default.isExecutableFile(atPath: Self.nettopPath) else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.nettopPath)
        // -P per-process summary, -L 2 two samples (second is a delta with -d), -x raw numbers.
        process.arguments = ["-P", "-L", "2", "-d", "-s", String(max(1, seconds)), "-J", "bytes_in,bytes_out", "-x"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return Self.parse(output)
    }

    // MARK: - Parsing (pure, unit-tested)

    /// Parses CSV produced by `nettop -L 2`. Only the last sample block (the delta) is used.
    static func parse(_ output: String) -> [ProcessNetworkUsage] {
        var lastBlock: [Substring] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix(",") {         // header line starts a new sample block
                lastBlock = []
            } else {
                lastBlock.append(line)
            }
        }

        let rows = lastBlock.compactMap { line -> ProcessNetworkUsage? in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let bytesIn = UInt64(fields[1]),
                  let bytesOut = UInt64(fields[2]) else { return nil }

            // First field is "process name.pid"; the name itself may contain dots.
            let label = String(fields[0])
            guard let dot = label.lastIndex(of: "."),
                  let pid = Int32(label[label.index(after: dot)...]) else { return nil }
            return ProcessNetworkUsage(pid: pid, name: String(label[..<dot]), bytesIn: bytesIn, bytesOut: bytesOut)
        }

        return rows
            .filter { $0.bytesIn > 0 || $0.bytesOut > 0 }
            .sorted { $0.bytesIn + $0.bytesOut > $1.bytesIn + $1.bytesOut }
    }
}

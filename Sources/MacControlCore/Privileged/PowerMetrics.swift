//
//  PowerMetrics.swift
//  MacControlCore
//

import Foundation

/// CPU frequency, package power and thermal pressure, parsed from the helper's trimmed `powermetrics` output.
public struct PowerMetrics: Equatable {

    /// Estimated power of CPUs + graphics + system agent, watts.
    public var packageWatts: Double?
    /// Average CPU frequency, MHz, and how it compares with the nominal (base) frequency.
    public var averageMHz: Double?
    public var fractionOfNominal: Double?
    /// Frequency of each logical core, MHz, in core order.
    public var coreMHz: [Double] = []
    /// "Nominal", "Moderate", "Heavy", … as reported by macOS.
    public var thermalPressure: String?

    public init() {}

    /// Parses the lines kept by `PrivilegedOperations.filterPowerMetrics`.
    public static func parse(_ text: String) -> PowerMetrics {
        var result = PowerMetrics()
        var currentCore: Int?
        var cores: [Int: Double] = [:]

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let match = firstMatch(#"^CPU (\d+)$"#, in: line) {
                currentCore = Int(match[0])
            } else if let match = firstMatch(#"package power[^:]*:\s*([\d.]+)\s*W"#, in: line, caseInsensitive: true) {
                result.packageWatts = Double(match[0])
            } else if let match = firstMatch(#"^System Average frequency as fraction of nominal:\s*([\d.]+)%\s*\(([\d.]+)\s*Mhz\)"#, in: line, caseInsensitive: true) {
                result.fractionOfNominal = Double(match[0]).map { $0 / 100 }
                result.averageMHz = Double(match[1])
            } else if let match = firstMatch(#"^CPU Average frequency as fraction of nominal:\s*([\d.]+)%\s*\(([\d.]+)\s*Mhz\)"#, in: line, caseInsensitive: true) {
                if let core = currentCore, let mhz = Double(match[1]) { cores[core] = mhz }
            } else if let match = firstMatch(#"pressure level:\s*(\w+)"#, in: line, caseInsensitive: true) {
                result.thermalPressure = match[0]
            }
        }
        result.coreMHz = cores.sorted { $0.key < $1.key }.map { $0.value }
        if result.averageMHz == nil, !result.coreMHz.isEmpty {
            result.averageMHz = result.coreMHz.reduce(0, +) / Double(result.coreMHz.count)
        }
        return result
    }

    private static func firstMatch(_ pattern: String, in text: String, caseInsensitive: Bool = false) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

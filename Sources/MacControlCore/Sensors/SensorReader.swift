//
//  SensorReader.swift
//  MacControlCore
//

import Foundation

/// Reads temperatures and fan speeds from the SMC.
///
/// At creation the reader probes which candidate sensors exist on this Mac and only
/// reads those afterwards. A sensor that exists but returns an implausible value
/// is reported with `celsius == nil` ("no data") rather than a made-up number.
public final class SensorReader {

    /// Range of temperatures treated as plausible; anything else means the sensor is idle or broken.
    private static let plausibleRange = 1.0...125.0
    private static let maximumFans = 8

    public let modelIdentifier: String
    private let connection: SMCConnection?
    private let activeSensors: [SensorDescriptor]
    private let fanCount: Int

    /// `true` when the SMC could be opened.
    public var isAvailable: Bool { connection != nil }

    /// - Parameters:
    ///   - modelIdentifier: `hw.model` value; `nil` means the current Mac.
    ///   - connection: SMC client; defaults to a new connection (`nil` if unavailable).
    public init(modelIdentifier: String? = nil,
                connection: SMCConnection? = SMCConnection()) {
        let modelIdentifier = modelIdentifier ?? Sysctl.string("hw.model") ?? ""
        self.modelIdentifier = modelIdentifier
        self.connection = connection

        guard let connection = connection else {
            activeSensors = []
            fanCount = 0
            return
        }
        activeSensors = SensorCatalog.temperatureSensors(forModel: modelIdentifier)
            .filter { connection.hasKey($0.key) }
        let reportedFans = Int(connection.read(key: "FNum")?.numeric ?? 0)
        fanCount = min(max(0, reportedFans), Self.maximumFans)
    }

    /// Reads all active temperature sensors.
    public func readTemperatures() -> [TemperatureReading] {
        guard let connection = connection else { return [] }
        return activeSensors.map { sensor in
            let value = connection.read(key: sensor.key)?.numeric
            let valid = value.flatMap { Self.plausibleRange.contains($0) ? $0 : nil }
            return TemperatureReading(sensor: sensor, celsius: valid)
        }
    }

    /// Reads current, minimum and maximum speed of every fan.
    public func readFans() -> [FanReading] {
        guard let connection = connection else { return [] }
        return (0..<fanCount).map { index in
            FanReading(
                index: index,
                currentRPM: connection.read(key: "F\(index)Ac")?.numeric,
                minimumRPM: connection.read(key: "F\(index)Mn")?.numeric,
                maximumRPM: connection.read(key: "F\(index)Mx")?.numeric
            )
        }
    }
}

//
//  LoggedEvent.swift
//  MacControlCore
//

import Foundation

/// Kind of performance event recorded in the journal.
public enum EventKind: String, Codable, CaseIterable {
    case cpuLoad
    case overheating
    case memoryPressure
    case swapGrowth
    case diskAlmostFull
    case throttling
}

/// A period of trouble ("yesterday 14:20–14:45: CPU 95 %, 92 °C, Xcode, kernel_task").
public struct LoggedEvent: Codable, Identifiable, Equatable {

    public let id: UUID
    public let kind: EventKind
    public let start: Date
    /// `nil` while the event is still going on.
    public var end: Date?
    public var peakCPU: Double
    public var peakTemperature: Double?
    /// Lowest CPU speed limit seen, percent (throttling events).
    public var lowestSpeedLimit: Int?
    public var peakSwapBytes: UInt64?
    public var lowestFreeFraction: Double?
    /// Three busiest applications during the event.
    public var topProcesses: [String]

    public var isOngoing: Bool { end == nil }

    public func duration(now: Date = Date()) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }

    public init(id: UUID = UUID(), kind: EventKind, start: Date, end: Date? = nil,
                peakCPU: Double = 0, peakTemperature: Double? = nil, lowestSpeedLimit: Int? = nil,
                peakSwapBytes: UInt64? = nil, lowestFreeFraction: Double? = nil, topProcesses: [String] = []) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.peakCPU = peakCPU
        self.peakTemperature = peakTemperature
        self.lowestSpeedLimit = lowestSpeedLimit
        self.peakSwapBytes = peakSwapBytes
        self.lowestFreeFraction = lowestFreeFraction
        self.topProcesses = topProcesses
    }
}

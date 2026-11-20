//
//  History.swift
//  MacControlCore
//

import Foundation

/// Time span shown on the history charts.
public enum HistoryRange: String, CaseIterable, Codable {
    case hour, day, week

    /// Length of the span in seconds.
    public var span: TimeInterval {
        switch self {
        case .hour: return 3_600
        case .day:  return 86_400
        case .week: return 604_800
        }
    }

    /// Width of one stored point: 5 s for the hour, 1 min for the day, 10 min for the week.
    public var bucket: TimeInterval {
        switch self {
        case .hour: return 5
        case .day:  return 60
        case .week: return 600
        }
    }
}

/// One averaged measurement in a history tier.
public struct HistoryPoint: Codable, Equatable {

    /// Start of the bucket, seconds since 1970.
    public var time: TimeInterval
    public var cpu: Double              // 0...1
    public var memory: Double           // 0...1
    public var diskRead: Double         // bytes/s
    public var diskWrite: Double        // bytes/s
    public var networkDown: Double      // bytes/s
    public var networkUp: Double        // bytes/s
    public var cpuTemperature: Double?  // °C
    /// Busiest applications during the bucket (up to three, busiest first).
    public var topProcesses: [String]

    public var date: Date { Date(timeIntervalSince1970: time) }

    public init(time: TimeInterval, cpu: Double, memory: Double, diskRead: Double, diskWrite: Double,
                networkDown: Double, networkUp: Double, cpuTemperature: Double?, topProcesses: [String]) {
        self.time = time
        self.cpu = cpu
        self.memory = memory
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.networkDown = networkDown
        self.networkUp = networkUp
        self.cpuTemperature = cpuTemperature
        self.topProcesses = topProcesses
    }
}

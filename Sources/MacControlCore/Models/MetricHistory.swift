//
//  MetricHistory.swift
//  MacControlCore
//

import Foundation

/// Short in-memory history of the main metrics, used for live sparklines.
/// Long-term history (hour/day/week, persisted) is a later development stage.
public struct MetricHistory {

    public static let defaultCapacity = 120

    public private(set) var cpu: RingBuffer<Double>
    public private(set) var memory: RingBuffer<Double>
    public private(set) var diskRead: RingBuffer<Double>
    public private(set) var diskWrite: RingBuffer<Double>
    public private(set) var networkDown: RingBuffer<Double>
    public private(set) var networkUp: RingBuffer<Double>
    public private(set) var cpuTemperature: RingBuffer<Double>

    public init(capacity: Int = MetricHistory.defaultCapacity) {
        cpu = RingBuffer(capacity: capacity)
        memory = RingBuffer(capacity: capacity)
        diskRead = RingBuffer(capacity: capacity)
        diskWrite = RingBuffer(capacity: capacity)
        networkDown = RingBuffer(capacity: capacity)
        networkUp = RingBuffer(capacity: capacity)
        cpuTemperature = RingBuffer(capacity: capacity)
    }

    /// Appends the values of a new snapshot to every series.
    public mutating func record(_ snapshot: SystemSnapshot) {
        cpu.append(snapshot.cpu.total)
        memory.append(snapshot.memory.usedFraction)
        diskRead.append(snapshot.disk.readBytesPerSecond)
        diskWrite.append(snapshot.disk.writeBytesPerSecond)
        networkDown.append(snapshot.network.downloadBytesPerSecond)
        networkUp.append(snapshot.network.uploadBytesPerSecond)
        if let temperature = snapshot.cpuTemperature {
            cpuTemperature.append(temperature)
        }
    }
}

//
//  NetworkStats.swift
//  MacControlCore
//

import Foundation

/// Aggregate network throughput over physical interfaces.
public struct NetworkStats: Equatable {

    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    public init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }

    public static let zero = NetworkStats(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
}

/// Network traffic of a single process during the last measurement window.
public struct ProcessNetworkUsage: Equatable, Identifiable {

    public let pid: Int32
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.pid = pid
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

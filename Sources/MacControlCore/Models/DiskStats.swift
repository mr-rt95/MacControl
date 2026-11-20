//
//  DiskStats.swift
//  MacControlCore
//

import Foundation

/// Capacity of the startup volume and current disk throughput.
public struct DiskStats: Equatable {

    /// Total capacity of the startup volume, bytes.
    public let totalBytes: UInt64
    /// Space available for important usage, including purgeable space, bytes.
    public let availableBytes: UInt64
    /// Bytes read per second since the previous sample.
    public let readBytesPerSecond: Double
    /// Bytes written per second since the previous sample.
    public let writeBytesPerSecond: Double

    public init(totalBytes: UInt64, availableBytes: UInt64,
                readBytesPerSecond: Double, writeBytesPerSecond: Double) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }

    public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }

    /// Fraction of the volume that is in use, `0...1`.
    public var usedFraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }

    /// Fraction of the volume that is free, `0...1`.
    public var freeFraction: Double { totalBytes == 0 ? 0 : 1 - usedFraction }

    public static let empty = DiskStats(totalBytes: 0, availableBytes: 0,
                                        readBytesPerSecond: 0, writeBytesPerSecond: 0)
}

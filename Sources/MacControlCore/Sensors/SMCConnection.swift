//
//  SMCConnection.swift
//  MacControlCore
//

import Foundation
import IOKit

/// A raw value read from the SMC.
public struct SMCValue: Equatable {
    /// Four-character data type, e.g. `sp78`.
    public let type: String
    public let bytes: [UInt8]

    /// Numeric interpretation, when the type is supported by `SMCValueDecoder`.
    public var numeric: Double? { SMCValueDecoder.decode(type: type, bytes: bytes) }
}

/// Low-level client for the `AppleSMC` IOKit service.
///
/// Read-only by design: the project never writes SMC keys (fan control is out of scope).
/// All calls are serialized with a lock, so one instance may be shared between threads.
public final class SMCConnection {

    // MARK: - Kernel interface

    /// Mirrors the kernel's `SMCKeyData_t`. Explicit padding reproduces the C layout
    /// because Swift does not pad nested structs to their stride.
    struct Parameters {
        struct Version {
            var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
            var release: UInt16 = 0
        }
        struct PowerLimit {
            var version: UInt16 = 0, length: UInt16 = 0
            var cpuLimit: UInt32 = 0, gpuLimit: UInt32 = 0, memoryLimit: UInt32 = 0
        }
        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
            var padding0: UInt8 = 0, padding1: UInt8 = 0, padding2: UInt8 = 0
        }
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

        var key: UInt32 = 0
        var version = Version()
        var powerLimit = PowerLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 {
        case readBytes = 5
        case readKeyByIndex = 8
        case readKeyInfo = 9
    }

    /// Selector of the SMC "handle YPC event" user-client method.
    private static let handleEventSelector: UInt32 = 2

    // MARK: - State

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var keyInfoCache: [UInt32: (size: UInt32, type: UInt32)] = [:]

    /// Opens the SMC. Returns `nil` when the service is missing or access is denied.
    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Public API

    /// Reads a key. Returns `nil` when the key does not exist or cannot be read.
    public func read(key: String) -> SMCValue? {
        lock.lock()
        defer { lock.unlock() }
        return readLocked(code: SMCValueDecoder.fourCC(key))
    }

    /// `true` if the SMC knows the key (regardless of its current value).
    public func hasKey(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return keyInfoLocked(code: SMCValueDecoder.fourCC(key)) != nil
    }

    /// Enumerates every key the SMC exposes. Intended for diagnostics only (a few hundred calls).
    public func allKeys() -> [String] {
        let count = Int(read(key: "#KEY")?.numeric ?? 0)
        lock.lock()
        defer { lock.unlock() }
        return (0..<count).compactMap { index in
            var input = Parameters()
            input.command = Command.readKeyByIndex.rawValue
            input.data32 = UInt32(index)
            guard let output = call(&input), output.result == 0 else { return nil }
            return SMCValueDecoder.string(fromFourCC: output.key)
        }
    }

    // MARK: - Private (callers hold the lock)

    private func keyInfoLocked(code: UInt32) -> (size: UInt32, type: UInt32)? {
        if let cached = keyInfoCache[code] { return cached }
        var input = Parameters()
        input.key = code
        input.command = Command.readKeyInfo.rawValue
        guard let output = call(&input), output.result == 0, output.keyInfo.dataSize > 0 else { return nil }
        let info = (size: output.keyInfo.dataSize, type: output.keyInfo.dataType)
        keyInfoCache[code] = info
        return info
    }

    private func readLocked(code: UInt32) -> SMCValue? {
        guard let info = keyInfoLocked(code: code) else { return nil }
        var input = Parameters()
        input.key = code
        input.keyInfo.dataSize = info.size
        input.command = Command.readBytes.rawValue
        guard let output = call(&input), output.result == 0 else { return nil }

        let size = min(Int(info.size), 32)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
        return SMCValue(type: SMCValueDecoder.string(fromFourCC: info.type), bytes: bytes)
    }

    private func call(_ input: inout Parameters) -> Parameters? {
        var output = Parameters()
        var outputSize = MemoryLayout<Parameters>.stride
        let status = IOConnectCallStructMethod(
            connection, Self.handleEventSelector,
            &input, MemoryLayout<Parameters>.stride,
            &output, &outputSize
        )
        return status == KERN_SUCCESS ? output : nil
    }
}

//
//  SMCValueDecoder.swift
//  MacControlCore
//

import Foundation

/// Decodes raw SMC byte payloads into numbers according to their SMC data type.
public enum SMCValueDecoder {

    /// - Parameters:
    ///   - type: Four-character SMC data type, e.g. `sp78`, `fpe2`, `flt `.
    ///   - bytes: Raw payload as returned by the SMC (big-endian for fixed-point/integers).
    /// - Returns: The numeric value, or `nil` for unsupported types or short payloads.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "sp78":                       // signed 7.8 fixed point (temperatures)
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2":                       // unsigned 14.2 fixed point (fan speeds)
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "fp88":                       // unsigned 8.8 fixed point
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 256
        case "flt ":                       // IEEE 754 single, little-endian on Intel SMC
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "si8 ":
            return bytes.first.map { Double(Int8(bitPattern: $0)) }
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }

    /// Converts a four-character string to the 32-bit key the SMC expects.
    public static func fourCC(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// Converts a 32-bit SMC key back to its four-character string.
    public static func string(fromFourCC value: UInt32) -> String {
        let bytes = [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }
}

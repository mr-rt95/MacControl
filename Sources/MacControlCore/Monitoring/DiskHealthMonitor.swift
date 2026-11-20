//
//  DiskHealthMonitor.swift
//  MacControlCore
//

import Foundation

/// Reads the SMART status of the startup drive through `diskutil`.
/// The result changes rarely, so callers should query it infrequently (e.g. every 30 minutes).
public final class DiskHealthMonitor {

    private let nvme = NVMeMonitor()

    public init() {}

    public func read() -> DiskHealth {
        let base = readBasic()
        return DiskHealth(smart: base.smart, isSolidState: base.isSolidState, mediaName: base.mediaName, wear: nvme.read())
    }

    private func readBasic() -> DiskHealth {
        guard let plist = Self.diskutilInfo("/") else { return .unknown }
        var info = plist

        // On APFS the status may only be present on the physical store; follow it if needed.
        if info["SMARTStatus"] == nil,
           let stores = info["APFSPhysicalStores"] as? [[String: Any]],
           let store = stores.first?["APFSPhysicalStore"] as? String,
           let physical = Self.diskutilInfo(Self.wholeDisk(of: store)) {
            info = physical
        }
        return Self.parse(info)
    }

    // MARK: - Parsing (pure, unit-tested)

    static func parse(_ info: [String: Any]) -> DiskHealth {
        let status: SMARTStatus
        switch (info["SMARTStatus"] as? String)?.lowercased() {
        case "verified"?:                 status = .verified
        case "failing"?:                  status = .failing
        case "not supported"?:            status = .notSupported
        default:                          status = .unknown
        }
        return DiskHealth(smart: status,
                          isSolidState: info["SolidState"] as? Bool,
                          mediaName: info["MediaName"] as? String)
    }

    /// `disk0s2` → `disk0`.
    static func wholeDisk(of identifier: String) -> String {
        guard identifier.hasPrefix("disk") else { return identifier }
        let characters = Array(identifier)
        var end = 4
        while end < characters.count, characters[end].isNumber { end += 1 }
        return String(characters[0..<end])
    }

    private static func diskutilInfo(_ target: String) -> [String: Any]? {
        guard let output = CommandRunner.run("/usr/sbin/diskutil", ["info", "-plist", target]),
              let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist
    }
}

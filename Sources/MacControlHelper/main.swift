//
//  main.swift
//  MacControlHelper
//
//  Privileged helper daemon, started by launchd on demand when MacControl connects to its Mach service.
//  It runs as root, so it does as little as possible: a fixed list of operations (see
//  MacControlHelperProtocol), each re-validated here, and only for a client signed by the same team.
//

import Foundation
import MacControlCore

/// Signer identity baked into this binary's embedded Info.plist by the build script (Team ID or certificate hash).
/// `nil` for unsigned builds.
let trust = SigningTrust.current

if CommandLine.arguments.contains("--print-config") {
    print("service: \(HelperConstants.machServiceName)")
    switch trust {
    case .team(let id)?:         print("trust: team \(id)")
    case .certificate(let h)?:   print("trust: certificate \(h)")
    case nil:                    print("trust: (none — unsigned build, all connections are refused)")
    }
    exit(0)
}

guard #available(macOS 13.0, *) else {
    // Client verification needs macOS 13; without it the helper must not accept anyone.
    FileHandle.standardError.write(Data("MacControlHelper requires macOS 13 or newer.\n".utf8))
    exit(EXIT_FAILURE)
}

let operations = PrivilegedOperations()
operations.purgeQuarantine(olderThanDays: 30)      // forget quarantined leftovers after 30 days

let requirement = trust?.clientRequirement
let delegate = HelperListenerDelegate(service: HelperService(operations: operations), requirement: requirement)
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()

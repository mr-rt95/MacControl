//
//  HelperService.swift
//  MacControlCore
//

import Foundation

/// The object exported over XPC: forwards each request to `PrivilegedOperations`.
public final class HelperService: NSObject, MacControlHelperProtocol {

    private let operations: PrivilegedOperations

    public init(operations: PrivilegedOperations = PrivilegedOperations()) {
        self.operations = operations
    }

    public func protocolVersion(reply: @escaping (Int) -> Void) {
        reply(HelperConstants.protocolVersion)
    }

    public func deleteTimeMachineSnapshot(_ name: String, reply: @escaping (Bool, String?) -> Void) {
        let failure = operations.deleteSnapshot(named: name)
        reply(failure == nil, failure?.rawValue)
    }

    public func moveSystemLeftover(_ path: String, bundleIdentifier: String, reply: @escaping (String?, String?) -> Void) {
        switch operations.moveLeftover(path: path, bundleIdentifier: bundleIdentifier) {
        case .success(let id): reply(id, nil)
        case .failure(let failure): reply(nil, failure.rawValue)
        }
    }

    public func restoreQuarantined(_ id: String, reply: @escaping (Bool, String?) -> Void) {
        let failure = operations.restore(id: id)
        reply(failure == nil, failure?.rawValue)
    }

    public func setDaemonEnabled(label: String, plistPath: String, enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        let failure = operations.setDaemon(label: label, plistPath: plistPath, enabled: enabled)
        reply(failure == nil, failure?.rawValue)
    }

    public func terminateProcess(_ pid: Int32, force: Bool, reply: @escaping (Bool, String?) -> Void) {
        let failure = operations.terminate(pid: pid, force: force)
        reply(failure == nil, failure?.rawValue)
    }

    public func readProcesses(reply: @escaping (Data?, String?) -> Void) {
        switch operations.processSamples() {
        case .success(let data): reply(data, nil)
        case .failure(let failure): reply(nil, failure.rawValue)
        }
    }

    public func readPowerMetrics(reply: @escaping (String?, String?) -> Void) {
        switch operations.powerMetrics() {
        case .success(let text): reply(text, nil)
        case .failure(let failure): reply(nil, failure.rawValue)
        }
    }
}

/// Accepts XPC connections only from the genuine MacControl app.
///
/// The check is a code-signing requirement tied to the team that signed this helper. A build without a team
/// (ad-hoc signed) has no requirement to enforce, so it refuses every connection instead of trusting anyone.
public final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {

    private let service: MacControlHelperProtocol
    private let requirement: String?
    private let skipsVerificationForTests: Bool

    public init(service: MacControlHelperProtocol = HelperService(), requirement: String?) {
        self.service = service
        self.requirement = requirement
        self.skipsVerificationForTests = false
    }

    /// Test-only: lets an in-process client connect without a signature.
    init(service: MacControlHelperProtocol, testingWithoutVerification: Bool) {
        self.service = service
        self.requirement = nil
        self.skipsVerificationForTests = testingWithoutVerification
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if !skipsVerificationForTests {
            guard let requirement = requirement else { return false }
            if #available(macOS 13.0, *) {
                connection.setCodeSigningRequirement(requirement)
            } else {
                return false      // cannot verify the client on macOS 12: refuse
            }
        }
        connection.exportedInterface = NSXPCInterface(with: MacControlHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    // MARK: - Requirement strings

    /// Requirement the helper imposes on its client (the app).
    public static func clientRequirement(teamID: String) -> String { SigningTrust.team(teamID).clientRequirement }

    /// Requirement the app imposes on the helper it talks to.
    public static func helperRequirement(teamID: String) -> String { SigningTrust.team(teamID).helperRequirement }
}

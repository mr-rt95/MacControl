//
//  HelperClient.swift
//  MacControlCore
//

import Foundation

/// App-side connection to the privileged helper.
///
/// Calls are synchronous with a time limit, meant for background queues. The connection is verified against
/// the helper's code signature; without a team ID (unsigned build) it refuses to connect at all.
public final class HelperClient {

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private let makeConnection: () -> NSXPCConnection?
    private let timeout: TimeInterval

    /// Connects to the installed helper daemon.
    /// - Parameter trust: how the helper's signature is verified; `nil` for unsigned builds (never connects).
    public convenience init(trust: SigningTrust?, timeout: TimeInterval = 30) {
        self.init(timeout: timeout) {
            guard let trust = trust else { return nil }
            guard #available(macOS 13.0, *) else { return nil }
            let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
            connection.setCodeSigningRequirement(trust.helperRequirement)
            return connection
        }
    }

    /// Convenience for Apple-issued certificates.
    public convenience init(teamID: String?, timeout: TimeInterval = 30) {
        self.init(trust: teamID.flatMap { $0.isEmpty ? nil : SigningTrust.team($0) }, timeout: timeout)
    }

    /// Uses a caller-provided connection (tests connect to an in-process listener).
    init(timeout: TimeInterval = 30, makeConnection: @escaping () -> NSXPCConnection?) {
        self.timeout = timeout
        self.makeConnection = makeConnection
    }

    deinit { connection?.invalidate() }

    // MARK: - Calls

    /// `true` when the helper answers and speaks the same protocol version.
    public func isReachable() -> Bool {
        let version: Int? = call { proxy, finish in proxy.protocolVersion { finish($0) } }
        return version == HelperConstants.protocolVersion
    }

    public func deleteSnapshot(_ name: String) -> HelperFailure? {
        failure(from: call { proxy, finish in proxy.deleteTimeMachineSnapshot(name) { ok, code in finish((ok, code)) } })
    }

    public func moveLeftover(path: String, bundleIdentifier: String) -> Result<String, HelperFailure> {
        guard let reply: (String?, String?) = call({ proxy, finish in
            proxy.moveSystemLeftover(path, bundleIdentifier: bundleIdentifier) { id, code in finish((id, code)) }
        }) else { return .failure(.helperUnavailable) }
        if let id = reply.0 { return .success(id) }
        return .failure(reply.1.flatMap(HelperFailure.init(rawValue:)) ?? .operationFailed)
    }

    public func restoreQuarantined(_ id: String) -> HelperFailure? {
        failure(from: call { proxy, finish in proxy.restoreQuarantined(id) { ok, code in finish((ok, code)) } })
    }

    public func setDaemon(label: String, plistPath: String, enabled: Bool) -> HelperFailure? {
        failure(from: call { proxy, finish in
            proxy.setDaemonEnabled(label: label, plistPath: plistPath, enabled: enabled) { ok, code in finish((ok, code)) }
        })
    }

    public func terminate(pid: Int32, force: Bool) -> HelperFailure? {
        failure(from: call { proxy, finish in proxy.terminateProcess(pid, force: force) { ok, code in finish((ok, code)) } })
    }

    /// Processes of every user, including root. Call often with a short `timeout`: it is polled while the app runs.
    public func processSamples() -> [ProcessSample]? {
        guard let reply: (Data?, String?) = call({ proxy, finish in proxy.readProcesses { data, code in finish((data, code)) } }),
              let data = reply.0 else { return nil }
        return try? JSONDecoder().decode([ProcessSample].self, from: data)
    }

    public func powerMetrics() -> Result<String, HelperFailure> {
        guard let reply: (String?, String?) = call({ proxy, finish in
            proxy.readPowerMetrics { text, code in finish((text, code)) }
        }) else { return .failure(.helperUnavailable) }
        if let text = reply.0 { return .success(text) }
        return .failure(reply.1.flatMap(HelperFailure.init(rawValue:)) ?? .operationFailed)
    }

    // MARK: - Plumbing

    private func failure(from reply: (Bool, String?)?) -> HelperFailure? {
        guard let reply = reply else { return .helperUnavailable }
        if reply.0 { return nil }
        return reply.1.flatMap(HelperFailure.init(rawValue:)) ?? .operationFailed
    }

    /// Sends one request and waits for its single reply. Returns `nil` if the helper is unreachable or too slow.
    private func call<T>(_ body: (MacControlHelperProtocol, @escaping (T) -> Void) -> Void) -> T? {
        guard let connection = activeConnection() else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        let resultLock = NSLock()

        let finish: (T) -> Void = { value in
            resultLock.lock()
            if result == nil { result = value }
            resultLock.unlock()
            semaphore.signal()
        }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
            self?.reset()
            semaphore.signal()               // wake the waiter; `result` stays nil
        }) as? MacControlHelperProtocol else { return nil }

        body(proxy, finish)
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        resultLock.lock()
        defer { resultLock.unlock() }
        return result
    }

    private func activeConnection() -> NSXPCConnection? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = connection { return existing }
        guard let created = makeConnection() else { return nil }
        created.remoteObjectInterface = NSXPCInterface(with: MacControlHelperProtocol.self)
        created.invalidationHandler = { [weak self] in self?.reset() }
        created.interruptionHandler = { [weak self] in self?.reset() }
        created.resume()
        connection = created
        return created
    }

    private func reset() {
        lock.lock()
        connection?.invalidate()
        connection = nil
        lock.unlock()
    }
}
